SHELL:=/bin/bash

pyenv:
	@python3 -m venv pyenv
	@source pyenv/bin/activate
	@pip3 install -r ./requirements-pip.txt

ansible:
	@cd ansible
	@ansible-galaxy collection install -r requirements.txt
	@ansible-galaxy role install -r requirements.txt
	@ansilbe-playbook -e "input_admin_pass=$(ANSIBLE_PASSWORD)" ./site.yml

all: pyenv ansible
