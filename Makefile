# vm-hardening-pipeline - run "make" to list the targets
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.RECIPEPREFIX = >
.DEFAULT_GOAL := help
.PHONY: help check test debian rocky windows all reports report-debian report-rocky report-windows clean-vms

# Remove a previous VM with the same name, then run the full Packer pipeline
define build
VBoxManage unregistervm $(2) --delete >/dev/null 2>&1 || true
rm -rf packer/$(1)/output-$(2)
cd packer/$(1) && packer init . && packer build . 2>&1 | tee ../../build-$(1).log
endef

help: ## List the targets
> @grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-15s %s\n", $$1, $$2}'

test: ## Unit tests for the report and list tools
> python3 -m unittest discover -s tests -v

check: test ## Static checks (Python, shell, Packer, Ansible)
> python3 -m py_compile reporting/*.py windows-hardening/*.py
> shellcheck -S warning scanning/linux/scan.sh reporting/make_report.sh
> for d in packer/debian packer/rocky packer/windows; do packer fmt -check $$d && packer validate -syntax-only $$d; done
> cd ansible && for p in playbooks/*.yml; do ansible-playbook "$$p" --syntax-check; done

debian: ## Debian 13: install, scan, harden, reboot, scan, report (about 55 min)
> $(call build,debian,debian13-cis)

rocky: ## Rocky Linux 10: same pipeline (about 35 min)
> $(call build,rocky,rocky10-cis)

windows: ## Windows Server 2025: same pipeline with HardeningKitty (about 60 min)
> $(call build,windows,ws2025-cis)

all: debian rocky windows ## All three platforms, one after the other

report-debian report-rocky report-windows: report-%:
> reporting/make_report.sh $*

reports: report-debian report-rocky report-windows ## Rebuild the three HTML reports from saved results

clean-vms: ## Remove the pipeline VMs (keeps the dev VM debian13-base)
> -VBoxManage unregistervm debian13-cis --delete
> -VBoxManage unregistervm rocky10-cis --delete
> -VBoxManage unregistervm ws2025-cis --delete
> rm -rf packer/*/output-*
