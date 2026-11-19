# Everything here runs offline: no AWS account, no credentials, no cost.
MODULES := modules/hub-spoke-vpc modules/transit-gateway modules/tgw-routing modules/vpc-endpoints modules/private-dns modules/probe-instance

.PHONY: all fmt validate test scan
all: fmt validate test scan

fmt:
	terraform fmt -check -recursive

validate:
	@for d in $(MODULES) envs/lab; do \
	  echo "== validate $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d validate || exit 1; \
	done

test:
	@for d in $(MODULES) envs/lab; do \
	  echo "== test $$d"; \
	  terraform -chdir=$$d init -backend=false -input=false >/dev/null && terraform -chdir=$$d test || exit 1; \
	done

scan:
	checkov -d . --framework terraform --skip-path '.terraform' --compact --quiet
