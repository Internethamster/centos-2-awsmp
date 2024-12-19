.ONESHELL:
SHELL:=/bin/bash
.phony: pyenv ansible_build jenkins_build std_build
	JENKINS_PASSWORD ?= "FileTheThingsThatIFile"


setup:
	@chmod +x centos-2-awsmp/create_db.py
	@centos-2-awsmp/create_db.py
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

std_build:
	@cd std-build
	@./image-builder-8-stream.sh
	@./image-builder-9-stream.sh

cn_build:
	@cd cn-build
	@./image-builder-8-stream.sh
	@./image-builder-9-stream.sh

jenkins_build: ansible_build
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./site.yml

image_build: ansible_build
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./build.yml

all: pyenv ansible_build # jenkins_build image_build
