# Confidential Clusters integration tests

The integration tests evaluate if the operator performs as expected with OpenShift MachineSets. It creates real confidential MachineSet replicas on supported backends.

Environment variables from the [upstream tests](https://github.com/trusted-execution-clusters/operator/tree/main/tests) are also supported:
- `TEST_NAMESPACE_PREFIX`
- `AZURE_RESOURCE_ID` (bootable image with trustee-attester, required for Azure, formatted `/resourcegroups/…/images/…/versions/…`)

Additionally, `BOOTC_IMAGE` must be set with a bootable container image to prevent updates to non-trustee-attester images.

## Usage

```
$ make AZURE_RESOURCE_ID=… BOOTC_IMAGE=… scale-tests
```

## Supported backends (auto-detected)

- Azure
