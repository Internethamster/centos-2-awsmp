SHELL:=/bin/bash



ansible:
	@cd ansible
	@ansible-galaxy collection install -r requirements.txt
	@ansible-galaxy role install -r requirements.txt
	@ansilbe-playbook -e "input_admin_pass=$(ANSIBLE_PASSWORD)" ./site.yml

all: ansible
