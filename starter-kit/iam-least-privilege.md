IAM least privilege

The task

When a kiosk sale has been completed, the order service creates one PDF receipt and stores it in object storage.

This role is allowed to grant only that production permission.

Identity: IAM role kijani-order-receipt-writer
Assumed by: the PaaS task role for the order service (ECS task role or Elastic Beanstalk instance profile)
Not assumed by: developers, CI, the storefront, or a human “break-glass” user

Why this is a separate role

If the access key is shared by the storefront, order API, and developer's laptop, a leaked key could view database snapshots, modify IAM settings, and delete receipts.

The order service must create a new object in one bucket using one prefix. It does not need to list the account, delete objects, or access another shop's prefix.

Policy

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "WriteReceiptsOnly",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::kijani-kiosk-receipts-prod/receipts/${aws:PrincipalTag/kioskId}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms"
        }
      }
    },
    {
      "Sid": "AllowKmsForThatBucket",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ],
      "Resource": "arn:aws:kms:af-south-1:111122223333:key/kijani-receipts-key",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "s3.af-south-1.amazonaws.com"
        }
      }
    }
  ]
}

When the account is created, replace the account ID and KMS key ID, but do not replace PutObject with s3:*.

Trust policy

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}

The compute platform can assume this role, and no long-lived access key exists on a laptop.

What this policy refuses

Column 1	Column 2
Request	Why it is denied
s3:ListBucket on the whole bucket	Stops a compromised task from enumerating every kiosk’s receipts
s3:GetObject	Writing a receipt is not the same as reading another shop’s receipt
s3:DeleteObject	A bug or an attacker cannot wipe the audit trail
s3:* on *	That is administrator access wearing an application name
iam:PassRole / iam:CreateUser	The app must not mint new identities
KMS use except via S3 in af-south-1	Stops the role being used as a general decryptor


How the kiosk boundary is enforced

The role is associated with a kioskId. The object key must begin with receipts/<that id>/. A task serving kiosk NBO-004 cannot write to receipts/NBO-009. If the runtime does not provide that tag, the service writes only to receipts/unassigned/ in the non-production account, never in production.

How this will be reviewed

* The pull request which alters this policy must indicate both the new action and the new resource.
* CI must reject the action "*" and the resource "*".
* After the first month the Access Advisor (or the equivalent) is checked and any unused actions are displayed.

Least privilege is not just a slogan; it consists of a list of verbs and a list of objects, and that list is kept short.