# AWS RDS Upgrade

Sample code for testing, use to upgrade AWS RDS MySQL version.

## 0. Prepare
* [Setup AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) with command `aws configure`.
* Add permissions for current user, follow this [guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_change-permissions.html). For testing, I added `AmazonRDSFullAccess` and `AmazonEC2FullAccess` to current user.
* From local terminal, set up variables:
  ```sh
  db_instance_name="rds-upgrade-testing"
  mysql_version="5.7.37"
  db_username="admin"
  db_password="dbPassword1"
  new_mysql_version="8.0.28"

  db_snapshot_name="backup-before-upgrade"
  ```

## 1. Create AWS RDS instance
I create a rds db instance, with `free-tier` template (20 GB SSD, instance class `db.t3.micro`), enable public access, so we can connect from Rails app localy.

```sh
# Create DB instance
aws rds create-db-instance \
    --engine mysql \
    --engine-version $mysql_version \
    --no-auto-minor-version-upgrade \
    --db-instance-identifier $db_instance_name \
    --allocated-storage 20 \
    --db-instance-class db.t3.micro \
    --master-username $db_username \
    --master-user-password $db_password \
    --publicly-accessible \
    --backup-retention-period 3

# Wait util DB instance becomes available
aws rds wait db-instance-available --db-instance-identifier $db_instance_name
```

This db instance will attach with default VPC and default Security Group of current region. We
need to add Inbound Rule to default Security Group, so that, we can access DB instance endpoint from local Rails app.

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
* Get the public db endpoint with this command:

```sh
aws rds describe-db-instances \
  --db-instance-identifier $db_instance_name \
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
* Create snapshot, so we can restore if there are any problems. It takes ~ 5
  minutes.

```sh
aws rds create-db-snapshot \
    --db-instance-identifier $db_instance_name \
    --db-snapshot-identifier $db_snapshot_name
```

* We can check snapshot status by using this command:

```sh
aws rds describe-db-snapshots \
  --db-instance-identifier $db_instance_name \
  --db-snapshot-identifier $db_snapshot_name \
  --output text \
  --query="DBSnapshots[*].[DBSnapshotIdentifier,Status]"
```

## 4. Upgrade database

* Firstly, please ensure that you run `rake db:ping` in Rails tab. We
  use this rake task to calculate downtime duration when upgrading MySQL.


### 4.1 Solution 1. Upgrade Directly
* From current console tab, run this command to upgrade MySQL version:

```sh
aws rds modify-db-instance \
    --db-instance-identifier $db_instance_name \
    --engine-version $new_mysql_version \
    --allow-major-version-upgrade \
    --apply-immediately
```

Now, RDS instance's status changes from `Available` to `Upgrading`. The instance shuts down in a special mode called a slow shutdown to ensure data consistency, so at first ~5 minutes, Rails app can still connect to DB.

It takes ~10-15 minutes to fully upgrade.

When `rake db:ping` stop, downtime duration will be shown. Now we can check new
MySQL engine version with this command, to ensure that DB instance is upgraded
successfull:

```sh
aws rds describe-db-instances \
  --db-instance-identifier $db_instance_name \
  --query 'DBInstances[*].{DBInstanceIdentifier:DBInstanceIdentifier,DBInstanceStatus:DBInstanceStatus,EngineVersion:EngineVersion}'

```

### 4.2 Solution 2. External replication based upgrade

* Create read replica from current db instance

```sh
read_replica_db_instance_name="read-replica-rds-upgrade-testing"

# Create read replica
aws rds create-db-instance-read-replica \
    --db-instance-identifier $read_replica_db_instance_name \
    --source-db-instance-identifier $db_instance_name

# Wait util read replica db instance becomes available (~8 minutes)
aws rds wait db-instance-available --db-instance-identifier $read_replica_db_instance_name
```

* Upgrade MySQL engine version of read replica

```sh
# Upgrade
aws rds modify-db-instance \
    --db-instance-identifier $read_replica_db_instance_name \
    --engine-version $new_mysql_version \
    --allow-major-version-upgrade \
    --apply-immediately

# Wait util read replica db instance becomes available (~13 minutes)
aws rds wait db-instance-available --db-instance-identifier $read_replica_db_instance_name

# Ensure that upgraded read replica has latest MySQL engine version
aws rds describe-db-instances \
  --db-instance-identifier $read_replica_db_instance_name \
  --query 'DBInstances[*].{DBInstanceIdentifier:DBInstanceIdentifier,DBInstanceStatus:DBInstanceStatus,EngineVersion:EngineVersion}'

```

* Promote read replica to be a standalone DB instance

```sh
# Promote read replica
aws rds promote-read-replica \
    --db-instance-identifier $read_replica_db_instance_name

# Wait util read replica db instance become available (~5 minutes)
aws rds wait db-instance-available --db-instance-identifier $read_replica_db_instance_name

```

* Change DB endpoint in Rails app to endpoint of Read Replica, which is promoted to standalone DB instance.

## 5. Rollback incase upgrade failed

### 5.1 In case we upgrade DB instance directly

* We can not rollback current instance (v8.0) to old instance (v5.7). We must restore a latest snapshot which is created before upgrade into a new db instance:

  ```sh
  new_db_instance_name="new-rds-upgrade-testing"

  aws rds restore-db-instance-from-db-snapshot \
    --db-instance-identifier $new_db_instance_name \
    --db-snapshot-identifier $db_snapshot_name
  ```

* Update the end points in route 53 to point to the new RDS. If there is no DNS endpoint, update the new RDS endpoints in your application configuration so that it starts fetching data from new MySQL RDS instance.

### 5.2 In case we upgrade by using external replication

* We just need to upgrade DNS endpoint to old endpoint (v5.7) cause this db instance is dependent with new RDS master instance (v8.0).

