#!/bin/bash

set -e  # Para o script caso ocorra erro
set -o pipefail

echo "🚀 Iniciando limpeza da conta AWS..."
chmod +x limpar_aws.sh

# 1️⃣ Deletar instâncias EC2
echo "🖥️ Apagando instâncias EC2..."
INSTANCES=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].InstanceId" --output text)
if [ -n "$INSTANCES" ]; then
  aws ec2 terminate-instances --instance-ids $INSTANCES
  echo "⌛ Aguardando instâncias serem encerradas..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCES
fi

# 2️⃣ Deletar Security Groups (exceto o default)
echo "🔒 Apagando Security Groups..."
SGS=$(aws ec2 describe-security-groups --query "SecurityGroups[?GroupName!='default'].GroupId" --output text)
for SG in $SGS; do
  aws ec2 delete-security-group --group-id $SG
done

# 3️⃣ Deletar repositórios ECR
echo "📦 Apagando repositórios ECR..."
ECR_REPOS=$(aws ecr describe-repositories --query "repositories[*].repositoryName" --output text)
for REPO in $ECR_REPOS; do
  aws ecr delete-repository --repository-name $REPO --force
done

# 4️⃣ Deletar roles IAM customizadas (não pode apagar roles usadas por serviços ativos)
echo "👤 Apagando roles IAM..."
ROLES=$(aws iam list-roles --query "Roles[*].RoleName" --output text)
for ROLE in $ROLES; do
  if [[ "$ROLE" != "AWSServiceRoleFor*" ]]; then
    aws iam delete-role --role-name "$ROLE" || true
  fi
done

# 5️⃣ Deletar Load Balancers
echo "🌐 Apagando Load Balancers..."
LBS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].LoadBalancerArn" --output text)
for LB in $LBS; do
  aws elbv2 delete-load-balancer --load-balancer-arn $LB
done

# 6️⃣ Deletar Target Groups
echo "🎯 Apagando Target Groups..."
TGS=$(aws elbv2 describe-target-groups --query "TargetGroups[*].TargetGroupArn" --output text)
for TG in $TGS; do
  aws elbv2 delete-target-group --target-group-arn $TG
done

# 7️⃣ Deletar bancos de dados RDS
echo "🗄️ Apagando instâncias RDS..."
RDS_INSTANCES=$(aws rds describe-db-instances --query "DBInstances[*].DBInstanceIdentifier" --output text)
for RDS in $RDS_INSTANCES; do
  aws rds delete-db-instance --db-instance-identifier $RDS --skip-final-snapshot
  echo "⌛ Aguardando RDS $RDS ser deletado..."
  aws rds wait db-instance-deleted --db-instance-identifier $RDS
done

# 8️⃣ Deletar registros DNS no Route 53
echo "🛣️ Apagando registros DNS do Route 53..."
HOSTED_ZONES=$(aws route53 list-hosted-zones --query "HostedZones[*].Id" --output text)
for ZONE in $HOSTED_ZONES; do
  ZONE_ID=$(echo $ZONE | cut -d'/' -f3)
  RECORD_SETS=$(aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query "ResourceRecordSets[?Type!='NS' && Type!='SOA']" --output json)
  echo $RECORD_SETS | jq -c '.[]' | while read -r RECORD; do
    NAME=$(echo $RECORD | jq -r '.Name')
    TYPE=$(echo $RECORD | jq -r '.Type')
    aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch "{\"Changes\":[{\"Action\":\"DELETE\",\"ResourceRecordSet\":$RECORD}]}"
  done
  aws route53 delete-hosted-zone --id $ZONE_ID
done


echo "✅ Limpeza concluída!"