import json
import os
import boto3

elbv2 = boto3.client("elbv2")

LISTENER_ARN = os.environ["LISTENER_ARN"]
BLUE_TG_ARN = os.environ["BLUE_TARGET_GROUP_ARN"]
GREEN_TG_ARN = os.environ["GREEN_TARGET_GROUP_ARN"]


def lambda_handler(event, context):
    """
    Triggered by an EventBridge rule when a CloudWatch alarm
    changes state.

    If the alarm state is ALARM, traffic is switched back to
    the Blue environment automatically.
    """

    print("Received Event:")
    print(json.dumps(event, indent=2))

    alarm_state = (
        event.get("detail", {})
             .get("state", {})
             .get("value")
    )

    if alarm_state != "ALARM":
        print(f"No rollback required. Alarm state: {alarm_state}")

        return {
            "statusCode": 200,
            "body": f"No action taken. Alarm state is '{alarm_state}'."
        }

    response = elbv2.modify_listener(
        ListenerArn=LISTENER_ARN,
        DefaultActions=[
            {
                "Type": "forward",
                "ForwardConfig": {
                    "TargetGroups": [
                        {
                            "TargetGroupArn": BLUE_TG_ARN,
                            "Weight": 100
                        },
                        {
                            "TargetGroupArn": GREEN_TG_ARN,
                            "Weight": 0
                        }
                    ]
                }
            }
        ]
    )

    print("Rollback completed successfully.")
    print(json.dumps(response, default=str))

    return {
        "statusCode": 200,
        "body": "Traffic automatically switched back to the Blue environment."
    }