## 0. Prepare
* [Setup AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) with command `aws configure`
* Add AWS RDS permission for current user, follow this [guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_change-permissions.html). For testing, I added `AmazonRDSFullAccess` and `AmazonEC2FullAccess` to current user.
* From local terminal, set up variables:
  ```sh
  rds_instance_name="rds-upgrade-testing"
  mysql_version="5.7.37"
  db_username="admin"
  db_password="dbPassword1"
  new_mysql_version="8.0.28"
  ```

## 1. Create AWS RDS instance
I create a rds db instance, with `free-tier` template (20 GB SSD, instance class `db.t3.micro`), enable public access, so we can connect from Rails app localy.

```sh
aws rds create-db-instance \
    --engine mysql \
    --engine-version $mysql_version \
    --no-auto-minor-version-upgrade \
    --db-instance-identifier $rds_instance_name \
    --allocated-storage 20 \
    --db-instance-class db.t3.micro \
    --master-username $db_username \
    --master-user-password $db_password \
    --publicly-accessible \
    --backup-retention-period 0
```

This db instance will attach with default VPC and default Security Group of current region. We
need to add Inbound Rule to default Security Group, so that, we can access DB
instance endpoint.

```sh
# Get default VPC id
vpc_id=`aws ec2 describe-vpcs \
  --filters "Name=isDefault, Values=true"
  --output text
  --query 'Vpcs[*].VpcId'`

# Get default Security Group id
sg_id=`aws ec2 describe-security-groups \
    --filters Name=vpc-id,Values=$vpc_id Name=group-name,Values=default \
    --output text \
    --query "SecurityGroups[*].GroupId"`

# Allow access from port 3306
aws ec2 authorize-security-group-ingress \
    --group-id $sg_id --protocol tcp --port 3306 --cidr 0.0.0.0/0
```

## 2. Try to connect AWS RDS from Rails app
* Wait util db instance is ready, we get the public db endpoint with this
  command:

```sh
aws rds describe-db-instances \
  --db-instance-identifier $rds_instance_name \
  --output text \
  --query 'DBInstances[*].Endpoint.Address'
```

* **Open another console tab** and go to `rails-sample-app`:
  ```sh
  bundle install
  cp .env.example .env

  # Update .env file with Public Endpoint, DB username and DB password

  # Create db
  rails db:prepare

  # seed data
  rake seed_data:article[100]

  # Ping to the database
  rake db:ping
  ```

## 3. Backup Data
