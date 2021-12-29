# This is a mkefile for the ansible project I use for infrastructure.
#
# make deploy - build or verify both systems are available
STAGE ?= development
ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_INVENTORY ?= ansible-inventory
INVENTORY ?= inventory/builder.aws_ec2.yaml

.PHONY: inventory deploy clean

inventory:
	$(ANSIBLE_INVENTORY) all -i $(INVENTORY) --list > ./inventory.json

deployx86:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=x86_64" ./deployment-std.yml -vvv


deployarm:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=arm64" ./deployment-std.yml -vvv

deploy: deployx86 deployarm inventory
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "stage=$(STAGE)" ./playbooks/image-maker.yml -vvv
cleanx86:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=x86_64" ./clean-std.yml -vvv

cleanarm:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=arm64" ./clean-std.yml -vvv

clean: cleanx86 cleanarm
	rm -f inventory.json

all: clean deploy inventory
