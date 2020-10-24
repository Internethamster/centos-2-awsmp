.ONESHELL:
SHELL:=/bin/bash
.phony: pyenv ansible
	JENKINS_PASSWORD ?= "FileTheThingsThatIFile"

pyenv:
	@python3 -m venv pyenv
	@source pyenv/bin/activate
	@pip3 install -r ./requirements-pip.txt

ansible:
	@cd ansible
	@ansible-galaxy collection install -r requirements.yml
	@ansible-galaxy role install -r requirements.yml
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./site.yml

all: pyenv ansible
