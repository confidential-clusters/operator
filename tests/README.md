# Confidential Clusters integration tests

The integration tests evaluate if the operator performs as expected with OpenShift MachineSets. It creates real confidential MachineSet replicas on supported backends.

Environment variables from the [upstream tests](https://github.com/trusted-execution-clusters/operator/tree/main/tests) are also supported:
- `APPROVED_IMAGE` (must be set to the same base as the boot image to prevent updates; upstream's Fedora will generally not work)
- `TEST_NAMESPACE_PREFIX`
- `AZURE_RESOURCE_ID` (bootable image with trustee-attester, required for Azure, formatted `/resourcegroups/…/images/…/versions/…`)

## Usage

```
$ make VIRT_PROVIDER=azure APPROVED_IMAGE=… AZURE_RESOURCE_ID=… scale-tests
```

## Supported backends (auto-detected)

- Azure (requires `VIRT_PROVIDER=azure` to be set to avoid AK registration)
