rds_instance_name="rds-upgrade-testing"
mysql_version="5.7.37"
db_username="admin"
db_password="dbPassword#1"

# Create db instance for testing
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

    # --vpc-security-group-ids mysecuritygroup \
    # --db-subnet-group mydbsubnetgroup \


# Get DB public endpoint
aws rds describe-db-instances \
  --db-instance-identifier $rds_instance_name \
  --output text \
  --query 'DBInstances[*].Endpoint.Address'


vpc_id=`aws ec2 describe-vpcs --filters "Name=isDefault, Values=true" --output text --query 'Vpcs[*].VpcId'`



aws rds describe-db-engine-versions \
  --engine mysql \
  --engine-version version-number \
  --query "DBEngineVersions[*].ValidUpgradeTarget[*].{EngineVersion:EngineVersion}" --output text

aws rds modify-db-instance \
    --db-instance-identifier $rds_instance_name \
    --engine-version $new_mysql_version \
    --allow-major-version-upgrade \
    --apply-immediately
