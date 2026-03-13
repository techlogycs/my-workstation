.PHONY: lint lint-ansible lint-nix format format-ansible format-nix check-ansible-tools check-nix-tools

NIX_DIR := ./nix
ANSIBLE_DIR := ansible
DOTFILES_USER ?= $(shell id -un)
DOTFILES_HOME ?= $(HOME)
NIX_SYSTEM ?= $(shell nix eval --impure --raw --expr builtins.currentSystem)

define require_command
	@command -v $(1) >/dev/null 2>&1 || { echo "Missing required command: $(1)"; exit 127; }
endef

lint: lint-ansible lint-nix

check-ansible-tools:
	$(call require_command,ansible-playbook)
	$(call require_command,ansible-lint)
	$(call require_command,yamllint)

check-nix-tools:
	$(call require_command,nix)
	$(call require_command,statix)

lint-ansible:
	@$(MAKE) check-ansible-tools
	ansible-playbook --syntax-check $(ANSIBLE_DIR)/local.yml
	ansible-lint $(ANSIBLE_DIR)
	yamllint .

lint-nix:
	@$(MAKE) check-nix-tools
	statix check $(NIX_DIR)
	DOTFILES_USER="$(DOTFILES_USER)" DOTFILES_HOME="$(DOTFILES_HOME)" NIX_SYSTEM="$(NIX_SYSTEM)" nix --extra-experimental-features "nix-command flakes" flake check --impure $(NIX_DIR)

format: format-ansible format-nix

format-ansible:
	@$(MAKE) check-ansible-tools
	ansible-lint --fix $(ANSIBLE_DIR)

format-nix:
	@$(MAKE) check-nix-tools
	cd $(NIX_DIR) && nix fmt .
