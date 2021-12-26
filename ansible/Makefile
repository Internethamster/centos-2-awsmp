# This is a mkefile for the ansible project I use for infrastructure.
#
# make deploy - build or verify both systems are available

ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_INVENTORY ?= ansible-inventory
INVENTORY ?= inventory/builder.aws_ec2.yaml

Inventory:
	$(ANSIBLE_INVENTORY) all -i $(INVENTORY) --list

deployx86:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=x86_64" ./deployment-std.yml -vvv

deployarm:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=arm64" ./deployment-std.yml -vvv

deploy: deployx86 deployarm


cleanx86:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=x86_64" ./clean-std.yml -vvv

cleanarm:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=arm64" ./clean-std.yml -vvv

clean: cleanx86 cleanarm

