upstream = ../operator
include $(upstream)/Makefile

# to avoid interpretation as argument delimiter
comma := ,

OPENSHIFT_API_DIR = $(shell go list -m -f '{{.Dir}}' github.com/openshift/api)
OPENSHIFT_API_LOCAL = config/crd/openshift-api

# Work around controller-gen rejecting invalid markers in openshift/api
# until https://github.com/openshift/api/issues/2978 is resolved
$(OPENSHIFT_API_LOCAL): $(OPENSHIFT_API_DIR)/go.mod
	rm -rf $(OPENSHIFT_API_LOCAL)
	mkdir -p $(OPENSHIFT_API_LOCAL)/machine/v1beta1
	cp $(OPENSHIFT_API_DIR)/go.mod $(OPENSHIFT_API_DIR)/go.sum $(OPENSHIFT_API_LOCAL)/
	cp $(OPENSHIFT_API_DIR)/machine/v1beta1/*.go $(OPENSHIFT_API_LOCAL)/machine/v1beta1/
	sed -i '/+kubebuilder:validation:Pattern=.*InventoryServiceTag/d' \
		$(OPENSHIFT_API_LOCAL)/machine/v1beta1/types_vsphereprovider.go

$(CRD_RS_PATH)/%.rs: $(CRD_YAML_PATH)/*_%.yaml $(KOPIUM) $(CRD_RS_PATH)
	$(KOPIUM) -f $< --derive Default > $@
	sed -Ei 'N; s/, Default\)\]\n(pub struct (MachineConfigPoolStatusPoolSynchronizersStatus(PoolSynchronizerType)?|AzureMachineProviderSpec(DataDisks|DiagnosticsBoot|SecurityProfileSettings)))/)]\n\1/; P; D' $@
	rustfmt $@

trusted-cluster-gen-downstream: $(MAKEFILE_DIR)api/trusted-cluster-gen.go
	cd $(MAKEFILE_DIR) && go build $<

generate-downstream: $(CONTROLLER_GEN) $(OPENSHIFT_API_LOCAL)
	$(call controller-gen,github.com/openshift/api/machineconfiguration/v1,*machineconfig{s$(comma)pools}*)
	$(call controller-gen,./$(OPENSHIFT_API_LOCAL)/machine/v1beta1,*{machinesets$(comma)azure*specs}*)

crds-rs-downstream: generate-downstream $(KOPIUM) $(CRD_RS_PATH)
	cd $(MAKEFILE_DIR) && $(MAKE) crds-rs
	$(MAKE) $(shell find $(CRD_YAML_PATH) -path $(OPENSHIFT_API_LOCAL) -prune -o -type f -print \
		| sed -E 's|$(CRD_YAML_PATH)/.*_(.*)\.yaml|$(CRD_RS_PATH)/\1.rs|')

INTEGRATION_TEST_FLAGS = -- --nocapture --test-threads=$(INTEGRATION_TEST_THREADS)
scale-tests: crds-rs-downstream trusted-cluster-gen-downstream
	UPSTREAM_DIR=$$(realpath ../operator) PLATFORM=openshift $(INTEGRATION_TEST_ENV) \
	cargo test --test scale $(INTEGRATION_TEST_FLAGS)
