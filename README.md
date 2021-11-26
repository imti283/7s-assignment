# 7s-assignment

## How to run -:
## Assumption - Private Subnet will try to create itself in default VPC's 'x.x.129.0/24' CIDR. If conflicts apply may fail.
Clone the Repo
Replace Access & Secret Key in terrafor.tfvars file
Replace Key_name with a keypair name you generated in aws
Run

  >```terraform init```
  
  >```terraform plan -out plan.out```
  
  *  **Expected plan should show** - ```Plan: 8 to add, 0 to change, 0 to destroy.```
    
  >```terraform apply plan.out```

## Browse the ALB URL you get on apply's output
