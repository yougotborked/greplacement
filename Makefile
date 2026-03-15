INSTALL_DIR ?= $(HOME)/.local/bin

.PHONY: install uninstall test lint

install:
	@mkdir -p $(INSTALL_DIR)
	@cp greplacement $(INSTALL_DIR)/grep
	@chmod +x $(INSTALL_DIR)/grep
	@echo "Installed to $(INSTALL_DIR)/grep"

uninstall:
	@rm -f $(INSTALL_DIR)/grep
	@echo "Removed $(INSTALL_DIR)/grep"

test:
	@bash tests/test_shim.sh

lint:
	@shellcheck greplacement install.sh tests/test_shim.sh

.DEFAULT_GOAL := install
