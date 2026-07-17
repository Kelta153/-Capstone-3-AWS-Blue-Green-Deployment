# AWS Blue-Green Deployment Capstone 3

A Blue-Green deployment architecture on AWS, built entirely with AWS CLI and Bash. No CloudFormation, no Terraform — every resource was created manually, scripted, and torn down manually, in order to understand each component involved rather than abstract it behind an IaC tool.

The end state is a self-healing deployment pipeline: an ALB shifts traffic between two EC2 environments (Blue/Green) using weighted target groups, CloudWatch watches target health, and an EventBridge → Lambda pipeline automatically rolls traffic back to Blue if Green becomes unhealthy.

## 1. Objectives

- Build a full Blue-Green network and compute stack using only the AWS CLI.
- Implement weighted ALB routing for staged rollouts (Blue 100 → Canary → 50/50 → Full Green).
- Detect unhealthy targets with CloudWatch and notify via SNS.
- Automate rollback with EventBridge and Lambda, with no human in the loop.
- Prove the rollback works by breaking the Green environment on purpose and observing the recovery.

## 2. Architecture

```mermaid
flowchart TB
    Internet((Internet)) --> ALB[Application Load Balancer]
    ALB -->|weighted forward| BlueTG[Blue Target Group]
    ALB -->|weighted forward| GreenTG[Green Target Group]
    BlueTG --> BlueEC2[Blue EC2<br/>Public Subnet A]
    GreenTG --> GreenEC2[Green EC2<br/>Public Subnet B]
    BlueEC2 --> RDS[(MySQL RDS<br/>Private Subnets)]
    GreenEC2 --> RDS

    GreenTG -.UnHealthyHostCount.-> Alarm[CloudWatch Alarm]
    Alarm -->|ALARM| SNS[SNS Topic]
    SNS --> Email[Email Notification]
    Alarm -->|state change| EventBridge[EventBridge Rule]
    EventBridge --> Lambda[Rollback Lambda]
    Lambda -->|ModifyListener: Blue 100 / Green 0| ALB
```

## 3. Repository Structure

```
.
├── config.sh              # Project-wide settings (region, CIDRs, instance types)
├── resources.env           # Resource IDs captured as scripts run
├── scripts/
│   ├── 01-network.sh        # VPC, IGW, subnets, route tables
│   ├── 02-security-groups.sh
│   ├── 03-ec2.sh             # Blue/Green instances, SSM role, key pair
│   ├── 04-rds.sh
│   ├── 05-alb.sh             # Target groups, ALB, listener
│   ├── 06-health-check.sh    # Staged weighted rollout (Blue → Canary → 50/50 → Green)
│   ├── 07-cloudwatch.sh      # SNS topic, subscription, alarm
│   ├── 08-lambda.sh          # Rollback Lambda, IAM role, packaging
│   ├── 09-eventbridge.sh     # Alarm-state rule wired to Lambda
│   └── 10-cleanup.sh         # Full teardown in dependency order
├── configs/                 # Generated listener/event-pattern JSON payloads
├── iam/                     # Trust and permission policies
├── lambda/                  # rollback.py + packaged zip
├── userdata/                # blue.sh / green.sh EC2 bootstrap scripts
└── keys/                    # Generated EC2 key pair
```

## 4. Network

`scripts/01-network.sh` provisions:

- 1 VPC (`10.0.0.0/16`), DNS support and hostnames enabled
- 1 Internet Gateway, attached to the VPC
- 2 public subnets (`10.0.1.0/24`, `10.0.2.0/24`) across two AZs, auto-assign public IP enabled
- 2 private subnets (`10.0.3.0/24`, `10.0.4.0/24`) for RDS
- A public route table (default route to the IGW) and a private route table, both associated to their respective subnets

All resource IDs are appended to `resources.env` so later scripts can `source` them.

![Region/AZ selection](images/region-AZ.png)
![VPC created](images/vpc1.png)
![VPC detail](images/vpc2.png)
![IGW created](images/IGW1.png)
![IGW attached](images/IGW2.png)
![Subnet A](images/sub1.png)
![Subnet B](images/sub2.png)
![Subnet detail](images/sub3.png)
![Route table 1](images/route1.png)
![Route table 2](images/route2.png)
![Route table 3](images/route3.png)
![Route table 4](images/route4.png)

**Issues encountered**

- Git Bash rewrites arguments that look like Unix paths into Windows paths, which breaks AWS CLI calls that expect literal strings (e.g. SSM parameter names, ARNs). Fixed by prefixing affected commands with `MSYS_NO_PATHCONV=1`.
- Exported shell variables didn't survive a terminal restart, breaking any script run in a new session. Fixed by persisting every resource ID to `resources.env` and sourcing it at the top of each script instead of relying on the shell environment.

## 5. Security Groups

`scripts/02-security-groups.sh` creates three groups:

| Security Group | Rule     | Source                       |
| -------------- | -------- | ---------------------------- |
| ALB-SG         | TCP 80   | `0.0.0.0/0`                  |
| WEB-SG         | TCP 80   | ALB-SG                       |
| WEB-SG         | TCP 22   | `0.0.0.0/0` (administration) |
| WEB-SG         | TCP 80   | `0.0.0.0/0` (temporary)      |
| RDS-SG         | TCP 3306 | WEB-SG                       |

The direct HTTP-from-internet rule on WEB-SG was added during troubleshooting, to hit the EC2 instances' public IPs directly and confirm Apache was serving content before the ALB was in the loop. It is not required once the ALB is validated and would be removed in a production configuration — the ALB-SG → WEB-SG path is the only one that should carry traffic.

![Security group 1](images/sg1.png)
![Security group 2](images/sg2.png)
![Security group 3](images/sg3.png)
![Security group 4](images/sg4.png)

## 6. EC2

`scripts/03-ec2.sh` launches the Blue and Green servers:

- AMI resolved dynamically at runtime via SSM Parameter Store (`/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64`), so the script always deploys the current Amazon Linux 2023 image instead of a hardcoded AMI ID.
- Blue → Public Subnet A, Green → Public Subnet B, both in WEB-SG.
- User data (`userdata/blue.sh`, `userdata/green.sh`) installs Apache and writes a static, color-coded `index.html` identifying the environment.
- An IAM role (`BlueGreenEC2SSMRole`) with `AmazonSSMManagedInstanceCore`, wrapped in an instance profile, is attached at launch so both instances are manageable through SSM Session Manager instead of SSH.

SSM was chosen over SSH for the rest of the project because it needs no open inbound port, no key distribution, and every session is logged in CloudTrail — a better fit for an instance that should only be reachable through the ALB.

![EC2 instance launch](images/EC2.png)
![EC2 instance detail](images/EC22.png)
![EC2 instance running](images/EC23.png)
![Green instance launch](images/EC2G.png)
![Green instance detail](images/EC2G2.png)
![SSM connect](images/ssm%201.png)
![SSM session](images/ssmA.png)
![SSM enabled](images/ssmenabled.png)

**Issues encountered**

- The SSM parameter path was silently rewritten by Git Bash's path conversion, causing `get-parameters` to fail. Same fix as above: `MSYS_NO_PATHCONV=1`.
- SSM Session Manager could not connect immediately after launch. Cause: the instance profile was attached to a running instance rather than at launch time in an earlier iteration, and the SSM agent only picks up new credentials after the instance profile association is refreshed. Fixed by reattaching the profile and rebooting the instance.
- The `aws ssm start-session` command requires the Session Manager plugin, which is not part of the base AWS CLI. Installed `session-manager-plugin` separately before SSM sessions would work.

## 7. Application Load Balancer

`scripts/05-alb.sh`:

- Creates `BlueGreen-Blue-TG` and `BlueGreen-Green-TG` (HTTP:80, health check path `/`).
- Registers the Blue and Green instances into their respective target groups.
- Creates an internet-facing ALB across both public subnets, with an HTTP:80 listener.
- Configures the listener's default action as a weighted forward rule (Blue 100 / Green 0 initially) instead of a single static target group, which is what makes staged traffic shifting possible later.

![Target group](images/TG.png)
![ALB created](images/ALB.png)
![Target group 2](images/TG2.png)
![ALB detail](images/ALB2.png)
![ALB listener](images/ALB3.png)
![Targets registered](images/ALBEC2.png)

**Issues encountered**

- Target groups reported `Target.NotInUse` after registration. Cause: the listener hadn't been created/modified to forward to them yet — a target group with no listener pointing at it never leaves that state. Fixed by completing the listener configuration.
- Passing the weighted `--default-actions` structure inline failed because Git Bash mangled the JSON quoting. Fixed by writing the payload to `configs/listener-config.json` and passing `file://configs/listener-config.json` instead of inlining it.

## 8. Deployment Validation

`scripts/06-health-check.sh` walks the listener through four weighted stages, pausing for confirmation at each step and printing the live listener weights and target health:

1. Blue 100% / Green 0%
2. Canary — Blue 90% / Green 10%
3. Validation — Blue 50% / Green 50%
4. Full Green — Blue 0% / Green 100%

At each stage, target health, listener weights, and browser behavior (which color page loads) were checked before proceeding to the next.

![Listener stage 1](images/Lism.png)
![Listener stage 2](images/lism2.png)
![Listener health check](images/lismgreen.png)
![Listener canary weights](images/lismcanary.png)
![Listener green weights](images/lismGreeenn.png)
![Listener on ALB](images/lismgrenalb.png)

## 9. Monitoring

`scripts/07-cloudwatch.sh`:

- Creates an SNS topic (`BlueGreenDeploymentAlerts`) and subscribes an email address, requiring manual confirmation before the script continues.
- Creates a CloudWatch alarm (`GreenTarget-UnHealthyHostCount`) on the `UnHealthyHostCount` metric for the Green target group, threshold `>= 1` over a single 60s period, with `notBreaching` treatment for missing data.
- Wires the alarm's action directly to the SNS topic, so any breach sends an email independent of the automated rollback path.

![SNS topic](images/snstopic.png)
![SNS confirmation](images/snscon.png)
![CloudWatch alarm creation](images/cloudwatchcreate.png)
![CloudWatch alarm console](images/claoudwatchui.png)

## 10. Lambda Rollback

`scripts/08-lambda.sh`:

- Packages `lambda/rollback.py` into a zip (falls back to PowerShell's `Compress-Archive` when `zip` isn't available).
- Creates `BlueGreenRollbackLambdaRole`, trusted by `lambda.amazonaws.com`, with `AWSLambdaBasicExecutionRole` plus a scoped `BlueGreenRollbackPolicy` limited to `elasticloadbalancing:ModifyListener` and `DescribeListeners` — the function can shift ALB traffic and nothing else.
- Deploys the function with `LISTENER_ARN`, `BLUE_TARGET_GROUP_ARN`, and `GREEN_TARGET_GROUP_ARN` as environment variables.

`lambda/rollback.py` reads the alarm state from the incoming EventBridge event. If the state is `ALARM`, it calls `modify_listener` to force the listener back to Blue 100% / Green 0%. Any other state is logged and ignored.

![Lambda IAM role](images/lambdarole.png)
![Rollback policy](images/albrollbackpolicy.png)
![Lambda function deployed](images/lambdafuntion.png)
![Lambda console](images/lambdaui.png)

**Issues encountered**

- No `zip` binary in the Git Bash environment. Initially worked around with `tar`, which Lambda doesn't accept as a deployment package; switched to a conditional that uses `zip` if present and falls back to `Compress-Archive` via PowerShell otherwise.
- Both target group ARNs ended up in a single environment variable after a copy/paste mistake while setting the Lambda configuration. Fixed by re-running `update-function-configuration` with the variables split correctly.
- Manually invoking the Lambda returned `"No action taken"`. This is correct, not a bug — a manual invoke carries no CloudWatch alarm payload, so `alarm_state` never equals `ALARM` and the function should decline to act.

## 11. EventBridge

`scripts/09-eventbridge.sh`:

- Creates rule `BlueGreenRollbackRule` matching `aws.cloudwatch` events where `detail-type` is `CloudWatch Alarm State Change`, the alarm name is `GreenTarget-UnHealthyHostCount`, and the new state is `ALARM`.
- Attaches the rollback Lambda as the rule's target.
- Grants EventBridge `lambda:InvokeFunction` permission scoped to that specific rule ARN.

![EventBridge rule](images/eventbridge.png)
![EventBridge invocation](images/eventbridgeinvoke.png)

## 12. Automated Rollback Test

This is the validation that proves the pipeline, not just the components. With traffic at 100% Green, an SSM session was opened directly to the Green instance and Apache was stopped:

```
sudo systemctl stop httpd
```

```mermaid
sequenceDiagram
    participant Green as Green EC2
    participant ALB
    participant CW as CloudWatch Alarm
    participant SNS
    participant EB as EventBridge
    participant L as Lambda

    Green->>Green: httpd stopped
    ALB->>Green: health check fails
    ALB->>CW: UnHealthyHostCount >= 1
    CW->>CW: state -> ALARM
    CW->>SNS: publish
    SNS->>SNS: email sent
    CW->>EB: alarm state change event
    EB->>L: invoke
    L->>ALB: ModifyListener (Blue 100 / Green 0)
    ALB->>ALB: traffic returns to Blue
```

Traffic returned to Blue automatically, with no manual listener change — confirmed both in the target health/listener output and by reloading the ALB URL in a browser and seeing the Blue page.

![Initial state 1](images/test1.png)
![Initial state 2](images/test2.png)
![Initial state 3](images/test%203.png)
![Apache stopped / target unhealthy](images/test4.png)
![Target health detail](images/test5.png)
![Alarm state](images/test6.png)
![Alarm detail](images/test7.png)
![SNS email received](images/testemail.png)
![EventBridge rule matched](images/testeventbridge.png)
![Lambda invoked](images/testlambda.png)
![Listener modified](images/testalb%201.png)
![Lambda execution logs](images/testcloudwatchlambdalogs.png)
![Browser back on Blue](images/testalbsbacktoblue.png)

## 13. Automation Scripts

| Script                  | Purpose                                                    |
| ----------------------- | ---------------------------------------------------------- |
| `01-network.sh`         | Creates the VPC, IGW, subnets, and route tables            |
| `02-security-groups.sh` | Creates and configures ALB, WEB, and RDS security groups   |
| `03-ec2.sh`             | Launches Blue/Green EC2 instances with SSM access          |
| `04-rds.sh`             | Creates the private MySQL RDS instance                     |
| `05-alb.sh`             | Creates target groups, the ALB, and the weighted listener  |
| `06-health-check.sh`    | Walks the listener through the staged Blue→Green rollout   |
| `07-cloudwatch.sh`      | Creates the SNS topic, subscription, and CloudWatch alarm  |
| `08-lambda.sh`          | Packages and deploys the rollback Lambda with its IAM role |
| `09-eventbridge.sh`     | Wires the alarm state change to the Lambda target          |
| `10-cleanup.sh`         | Tears down every resource in dependency order              |

## 14. Cleanup

`scripts/10-cleanup.sh` deletes resources in strict dependency order — each `delete_if_exists` call is tolerant of a resource already being gone, so the script is safe to re-run:

EventBridge rule/targets → CloudWatch alarm → SNS subscriptions/topic → Lambda function → Lambda IAM role/policies → ALB listener → ALB → target groups → EC2 instances → key pair → instance profile/EC2 IAM role → RDS instance/subnet group → security groups → route table associations/route tables → Internet Gateway → subnets → VPC.

## 15. Lessons Learned

- Dependency order matters as much on teardown as on setup — deleting a security group still attached to a listener, or a subnet still associated to a route table, fails outright.
- A target group is only ever as healthy as its listener configuration — `Target.NotInUse` isn't a target group problem, it's a listener problem.
- SSM Session Manager is a strictly better fit than SSH for infrastructure that shouldn't need an open inbound port or key management, and it comes with a session audit trail for free.
- EventBridge's alarm-state-change pattern is a clean way to drive automation off CloudWatch without polling anything.
- Scoping the Lambda's IAM policy to exactly `ModifyListener`/`DescribeListeners` on the ALB, rather than broader ELB permissions, kept the blast radius of the rollback function to exactly one action.
- None of this is proven until it's tested end-to-end — manually invoking the Lambda looked like a bug (`"No action taken"`) until the actual failure path was simulated and the full chain was watched firing in sequence.

## 16. Future Improvements

- CI/CD integration to trigger deployments instead of running scripts manually.
- Migrate the rollout mechanism to CodeDeploy for native deployment tracking.
- Explore Blue-Green on ECS instead of EC2 for faster environment cycling.
- Re-implement the stack in CloudFormation or Terraform once the manual model is fully understood.
- Multi-AZ RDS for database failover.
- HTTPS on the ALB via ACM instead of plain HTTP.
