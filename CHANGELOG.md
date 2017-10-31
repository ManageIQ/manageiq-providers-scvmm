# Change Log

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)


## Unreleased as of Sprint 72 ending 2017-10-30

### Added
- Handle vm_networks and subnets in cloning [(#27)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/27)
- Add CIDR information to subnet [(#24)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/24)

### Fixed
- Use ID property explicitly in update_vm_script [(#29)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/29)
- Fix logger debug statement [(#28)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/28)

## Unreleased as of Sprint 71 ending 2017-10-16

### Added
- SCVMM Networking Enhancements [(#19)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/19)

### Fixed
- Move path_to_uri to SCVMM refresh parser [(#22)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/22)

## Unreleased as of Sprint 68 ending 2017-09-04

### Added
- Providers
  - Validate credentials in raw_connect [(#16)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/16)

## Unreleased as of Sprint 66 ending 2017-08-07

### Added
- Providers
  - [(BZ#1474404)](https://bugzilla.redhat.com/show_bug.cgi?id=1474404) Force array context for VMs vnets and images [(#13)](https://github.com/ManageIQ/manageiq-providers-scvmm/pull/13)
