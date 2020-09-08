SHELL:=/bin/bash



ansible:
	@cd ansible
	@ansible-galaxy collection install -r requirements.txt
	@ansible-galaxy roles install -r requirements.txt	

all: ansible
