# This is a makefile for the ansible project I use for infrastructure.
#
# make deploy - build or verify both systems are available
STAGE ?= development
ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE_INVENTORY ?= ansible-inventory
INVENTORY ?= inventory/builder-std.aws_ec2.yaml
INVENTORY_CN ?= inventory/builder-cn.aws_ec2.yaml



.PHONY: inventory deploy clean

inventory:
	$(ANSIBLE_INVENTORY) all -i $(INVENTORY) --list --export > ./inventory-std.json
	$(ANSIBLE_INVENTORY) all -i $(INVENTORY_CN) --list --export > ./inventory-cn.json

deployx86:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=x86_64 partition=std" ./deployment-std.yml -vvv
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY_CN) -e "ec2_architecture=x86_64 partition=bjs" ./deployment-cn.yml -vvv

deployarm:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=arm64 partition=std" ./deployment-std.yml -vvv
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY_CN) -e "ec2_architecture=arm64 partition=bjs" ./deployment-cn.yml -vvv


deploy: deployx86 deployarm inventory
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "stage=$(STAGE) partition=std" ./playbooks/image-maker.yml
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "stage=$(STAGE) partition=std" ./playbooks/register_cs8_image.yml
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY_CN) -e "stage=$(STAGE) partition=bjs" ./playbooks/image-maker.yml
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY_CN) -e "stage=$(STAGE) partition=bjs" ./playbooks/register_cs8_image-cn.yml

cleanx86:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=x86_64 partition=std" ./clean-std.yml -vvv
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY_CN) -e "ec2_architecture=x86_64 partition=bjs" ./clean-cn.yml -vvv


cleanarm:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) -e "ec2_architecture=arm64 partition=std" ./clean-std.yml -vvv
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY_CN) -e "ec2_architecture=arm64 partition=bjs" ./clean-cn.yml -vvv


clean: cleanx86 cleanarm
	rm -f inventory-std.json
	rm -f inventory-cn.json

all: clean deploy inventory
