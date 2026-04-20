import base64
import hashlib
import hmac
import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client("ec2")
ssm = boto3.client("ssm")

PROJECT_NAME = os.environ["PROJECT_NAME"]
TRELLO_BOARD_ID = os.environ["TRELLO_BOARD_ID"]
TRELLO_READY_LIST_NAME = os.environ["TRELLO_READY_LIST_NAME"]
GITHUB_REPO = os.environ["GITHUB_REPO"]
EC2_LAUNCH_TEMPLATE_ID = os.environ["EC2_LAUNCH_TEMPLATE_ID"]
EC2_SUBNET_ID = os.environ["EC2_SUBNET_ID"]
ARTIFACTS_BUCKET = os.environ["ARTIFACTS_BUCKET"]


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")

    # Trello sends HEAD to verify the callback URL during webhook registration
    if method == "HEAD":
        return {"statusCode": 200, "body": ""}

    body = event.get("body") or ""
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    # Validate HMAC-SHA1 signature before processing
    api_secret = _get_ssm(f"/{PROJECT_NAME}/trello/api_secret")
    host = headers.get("host", "")
    stage = event.get("requestContext", {}).get("stage", "$default")
    callback_url = f"https://{host}/webhook/trello"

    signature = headers.get("x-trello-webhook", "")
    if not _valid_signature(body, signature, api_secret, callback_url):
        logger.warning("Invalid Trello webhook signature from %s", headers.get("x-forwarded-for"))
        return {"statusCode": 401, "body": "Unauthorized"}

    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": "Bad Request"}

    action = payload.get("action", {})
    action_type = action.get("type", "")
    logger.info("Received action type: %s", action_type)

    if action_type == "updateCard":
        _handle_card_update(action)
    elif action_type == "commentCard":
        _handle_comment(action)

    return {"statusCode": 200, "body": "OK"}


# ── Trello event handlers ────────────────────────────────────────────────────

def _handle_card_update(action: dict):
    data = action.get("data", {})
    list_after = data.get("listAfter", {})

    if list_after.get("name") != TRELLO_READY_LIST_NAME:
        return

    card = data.get("card", {})
    card_id = card.get("id")
    card_name = card.get("name", "Unnamed card")
    logger.info("Card moved to '%s': %s — %s", TRELLO_READY_LIST_NAME, card_id, card_name)

    api_key = _get_ssm(f"/{PROJECT_NAME}/trello/api_key")
    api_token = _get_ssm(f"/{PROJECT_NAME}/trello/api_token")
    card_desc = _fetch_card_description(card_id, api_key, api_token)

    _launch_harness(card_id, card_name, card_desc)


def _handle_comment(action: dict):
    data = action.get("data", {})
    card = data.get("card", {})
    card_id = card.get("id")
    comment_text = data.get("text", "")
    author = action.get("memberCreator", {}).get("username", "unknown")

    logger.info("Comment on card %s by %s", card_id, author)

    # Skip bot comments to avoid loops
    if comment_text.startswith("✅") or comment_text.startswith("❌"):
        logger.info("Skipping bot comment")
        return

    running = _find_running_instance(card_id)
    if running:
        instance_id = running["InstanceId"]
        logger.info("Sending iteration to running instance %s", instance_id)
        _send_iteration_command(instance_id, comment_text)
    else:
        logger.info("No running instance for card %s; launching new instance", card_id)
        api_key = _get_ssm(f"/{PROJECT_NAME}/trello/api_key")
        api_token = _get_ssm(f"/{PROJECT_NAME}/trello/api_token")
        card_name = card.get("name", "Unknown card")
        card_desc = _fetch_card_description(card_id, api_key, api_token)
        _launch_harness(card_id, card_name, card_desc, iteration_comment=comment_text)


# ── EC2 management ───────────────────────────────────────────────────────────

def _launch_harness(
    card_id: str,
    card_name: str,
    card_desc: str,
    iteration_comment: str = "",
):
    job_id = uuid.uuid4().hex[:8]
    job_param = f"/{PROJECT_NAME}/jobs/{card_id}"

    job_data = json.dumps({
        "card_id": card_id,
        "card_name": card_name,
        "card_desc": card_desc,
        "iteration_comment": iteration_comment,
        "github_repo": GITHUB_REPO,
        "artifacts_bucket": ARTIFACTS_BUCKET,
        "job_id": job_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
    })

    ssm.put_parameter(Name=job_param, Value=job_data, Type="String", Overwrite=True)

    user_data = base64.b64encode(
        f"""#!/bin/bash
export CARD_ID="{card_id}"
export JOB_PARAM="{job_param}"
export PROJECT_NAME="{PROJECT_NAME}"
/opt/harness/run.sh
""".encode()
    ).decode()

    response = ec2.run_instances(
        LaunchTemplate={"LaunchTemplateId": EC2_LAUNCH_TEMPLATE_ID, "Version": "$Latest"},
        MinCount=1,
        MaxCount=1,
        SubnetId=EC2_SUBNET_ID,
        UserData=user_data,
        TagSpecifications=[{
            "ResourceType": "instance",
            "Tags": [
                {"Key": "TrelloCardId", "Value": card_id},
                {"Key": "JobId", "Value": job_id},
                {"Key": "Name", "Value": f"invoiceshelf-harness-{card_id[:8]}"},
            ],
        }],
    )

    instance_id = response["Instances"][0]["InstanceId"]
    logger.info("Launched %s for card %s (job %s)", instance_id, card_id, job_id)


def _find_running_instance(card_id: str) -> dict | None:
    response = ec2.describe_instances(Filters=[
        {"Name": "tag:TrelloCardId", "Values": [card_id]},
        {"Name": "instance-state-name", "Values": ["pending", "running"]},
    ])
    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            return instance
    return None


def _send_iteration_command(instance_id: str, comment: str):
    escaped = comment.replace("'", "'\\''")
    ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Parameters={"commands": [
            f"echo '{escaped}' >> /home/ec2-user/harness_iteration.txt",
            "touch /home/ec2-user/harness_new_iteration",
        ]},
    )


# ── Helpers ──────────────────────────────────────────────────────────────────

def _valid_signature(body: str, signature: str, secret: str, callback_url: str) -> bool:
    if not signature:
        return False
    content = (body + callback_url).encode("utf-8")
    mac = hmac.new(secret.encode("utf-8"), content, hashlib.sha1)
    expected = base64.b64encode(mac.digest()).decode("utf-8")
    return hmac.compare_digest(expected, signature)


def _fetch_card_description(card_id: str, api_key: str, api_token: str) -> str:
    import urllib.request
    url = (
        f"https://api.trello.com/1/cards/{card_id}"
        f"?key={api_key}&token={api_token}&fields=desc,name"
    )
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
            return data.get("desc", "")
    except Exception:
        logger.exception("Failed to fetch card description for %s", card_id)
        return ""


def _get_ssm(name: str) -> str:
    response = ssm.get_parameter(Name=name, WithDecryption=True)
    return response["Parameter"]["Value"]
