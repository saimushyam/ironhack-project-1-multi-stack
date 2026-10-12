#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

import boto3
import yaml

ROOT = Path(__file__).resolve().parents[1]
TERRAFORM_DIR = ROOT / "infra" / "terraform"
INVENTORY_FILE = ROOT / "ansible" / "inventory" / "hosts.yml"
REGION = "us-east-1"

def terraform_output(name):
    result = subprocess.check_output(
        ["terraform", "output", "-json", name],
        cwd=TERRAFORM_DIR,
        text=True,
    )
    return json.loads(result)

groups = {
    "app": terraform_output("app_instance_ids"),
    "backend": terraform_output("backend_instance_ids"),
    "database": terraform_output("database_instance_ids"),
}

instance_ids = [instance_id for ids in groups.values() for instance_id in ids]

ec2 = boto3.client("ec2", region_name=REGION)
response = ec2.describe_instances(InstanceIds=instance_ids)

private_ips = {
    instance["InstanceId"]: instance["PrivateIpAddress"]
    for reservation in response["Reservations"]
    for instance in reservation["Instances"]
}

inventory = {
    "all": {
        "vars": {
            "ansible_connection": "amazon.aws.aws_ssm",
            "ansible_aws_ssm_region": REGION,
            "ansible_aws_ssm_bucket_name": (
                "ironhack-voting-ansible-ssm-686699774218-us-east-1"
            ),
            "ansible_python_interpreter": "/usr/bin/python3",
        },
        "children": {},
    }
}

for group, ids in groups.items():
    inventory["all"]["children"][group] = {
        "hosts": {
            instance_id: {
                "ansible_host": instance_id,
                "private_ip": private_ips[instance_id],
            }
            for instance_id in ids
        }
    }

# Initial deployment uses the first backend/database instance as its
# Redis/PostgreSQL endpoint. This is not automatic failover.
inventory["all"]["vars"]["redis_private_ip"] = private_ips[groups["backend"][0]]
inventory["all"]["vars"]["postgres_private_ip"] = private_ips[groups["database"][0]]

INVENTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
INVENTORY_FILE.write_text(
    yaml.safe_dump(inventory, sort_keys=False),
    encoding="utf-8",
)

print(f"Inventory generated: {INVENTORY_FILE}")
print(f"EC2 instances: {len(instance_ids)}")
