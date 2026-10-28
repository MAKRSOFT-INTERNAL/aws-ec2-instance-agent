import os
from datetime import datetime, timedelta, timezone

import boto3


def lambda_handler(event, context):
    region = os.environ["AWS_REGION"]
    repository = os.environ["REPOSITORY"]
    managed_by = os.environ["RUNNER_MANAGED_BY"]
    parameter_prefix = os.environ["PARAMETER_PREFIX"]
    max_age = int(os.environ["MAX_INSTANCE_AGE_SECONDS"])
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=max_age)

    ec2 = boto3.client("ec2", region_name=region)
    ssm = boto3.client("ssm", region_name=region)
    instances_to_terminate = []

    paginator = ec2.get_paginator("describe_instances")
    for page in paginator.paginate(
        Filters=[
            {"Name": "tag:ManagedBy", "Values": [managed_by]},
            {"Name": "tag:Repository", "Values": [repository]},
            {"Name": "instance-state-name", "Values": ["pending", "running", "stopping", "stopped"]},
        ]
    ):
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                if instance["LaunchTime"] < cutoff:
                    instances_to_terminate.append(instance["InstanceId"])

    if instances_to_terminate:
        ec2.terminate_instances(InstanceIds=instances_to_terminate)

    stale_parameters = []
    parameter_pages = ssm.get_paginator("get_parameters_by_path")
    for page in parameter_pages.paginate(Path=parameter_prefix, Recursive=True, WithDecryption=False):
        for parameter in page["Parameters"]:
            if parameter["LastModifiedDate"] < cutoff:
                stale_parameters.append(parameter["Name"])

    for parameter_name in stale_parameters:
        ssm.delete_parameter(Name=parameter_name)

    return {
        "terminated_instances": instances_to_terminate,
        "deleted_parameters": stale_parameters,
    }