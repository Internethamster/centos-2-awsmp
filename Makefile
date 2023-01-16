.ONESHELL:
SHELL:=/bin/bash
.phony: pyenv ansible_build jenkins_build
	JENKINS_PASSWORD ?= "FileTheThingsThatIFile"

pyenv:
	@python3 -m venv pyenv
	@source pyenv/bin/activate
	@pip3 install -r ./requirements-pip.txt

pyenv:
	@python3 -m venv pyenv
	@source pyenv/bin/activate
	@pip3 install -r ./requirements-pip.txt

ansible_build:
	@cd ansible
	@ansible-galaxy collection install -r requirements.yml
	@ansible-galaxy role install -r requirements.yml

jenkins_build: ansible_build
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./site.yml

image_build: ansible_build
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./build.yml

all: pyenv ansible_build # jenkins_build image_build
