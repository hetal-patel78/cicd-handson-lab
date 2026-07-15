#!/bin/bash
# version.sh
# Takes GitVersion output and produces the exact version strings
# the pipeline needs: fileVersion, artifactVersion, imageVersion, etc.
# In your company, this script is the bridge between GitVersion's
# semantic version and the specific formats required by:
#   - .NET assembly/file versioning
#   - Docker image tags
#   - NuGet package versions
#   - Octopus release versions
# Called by the "version" job in the CI/CD pipeline.

set -euo pipefail

# GitVersion outputs these environment variables:
#   GitVersion_SemVer, GitVersion_MajorMinorPatch, GitVersion_NuGetVersionV2
# This script transforms them into what the pipeline needs.

SEMVER="${GitVersion_SemVer:-0.0.0}"
MAJOR_MINOR_PATCH="${GitVersion_MajorMinorPatch:-0.0.0}"

# File version must be 3-part (used by Windows .dll metadata)
echo "fileVersion=$MAJOR_MINOR_PATCH"

# Artifact version (used by NuGet package)
echo "artifactVersion=$SEMVER"

# Docker image version (used for tagging)
echo "imageVersion=$SEMVER"

# Docker image name (includes registry path)
echo "imageName=mycompany.artifactory.io/my-subscription-service"

# Build number (used by Octopus to identify the build)
echo "buildNumber=$SEMVER+${GITHUB_RUN_NUMBER:-0}"
