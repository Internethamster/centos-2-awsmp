.ONESHELL:
SHELL:=/bin/bash
.phony: pyenv ansible
	JENKINS_PASSWORD ?= "FileTheThingsThatIFile"

<<<<<<< HEAD
pyenv:
	@python3 -m venv pyenv
	@source pyenv/bin/activate
	@pip3 install -r ./requirements-pip.txt

ansible:
||||||| merged common ancestors


ansible:
=======
pyenv:
	@python3 -m venv pyenv
	@source pyenv/bin/activate
	@pip3 install -r ./requirements-pip.txt

ansible_build:
>>>>>>> image-builder-7-fix
	@cd ansible
	@ansible-galaxy collection install -r requirements.yml
	@ansible-galaxy role install -r requirements.yml

jenkins_build: ansible_build
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./site.yml

image_build: ansible_build
	@ansible-playbook -e "input_admin_pass=$(JENKINS_PASSWORD)" ./build.yml

<<<<<<< HEAD
all: pyenv ansible
||||||| merged common ancestors
all: ansible
=======
all: pyenv jenkins_build 
>>>>>>> image-builder-7-fix
