#!/bin/bash
# © Copyright IBM Corporation 2019.
# LICENSE: Apache License, Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0)
#
# Instructions:
# Download build script: wget https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/0.24.1/build_nginx-ingress-controller.sh
# Execute build script: bash build_nginx-ingress-controller.sh    (provide -h for help)

set -e -o pipefail

PACKAGE_NAME="nginx-ingress-controller"
PACKAGE_VERSION="0.24.1"
CURDIR="$(pwd)"
BUILD_DIR="/usr/local"
GO_DEFAULT="$HOME/go"

TESTS="false"
FORCE="false"
LOG_FILE="$CURDIR/logs/${PACKAGE_NAME}-${PACKAGE_VERSION}-$(date +"%F-%T").log"
GO_INSTALL_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/Go/build_go.sh"
REPO_URL="https://raw.githubusercontent.com/linux-on-ibm-z/scripts/master/NGINX-ingress-controller/0.24.1/patch"

trap cleanup 0 1 2 ERR

#Check if directory exists
if [ ! -d "$CURDIR/logs/" ]; then
    mkdir -p "$CURDIR/logs/"
fi

# Need handling for RHEL 6.10 as it doesn't have os-release file
if [ -f "/etc/os-release" ]; then
    source "/etc/os-release"
else
    cat /etc/redhat-release >>"${LOG_FILE}"
    export ID="rhel"
    export VERSION_ID="6.10"
    export PRETTY_NAME="Red Hat Enterprise Linux 6.10"
fi

function prepare() {
    if command -v "sudo" >/dev/null; then
        printf -- 'Sudo : Yes\n' >>"$LOG_FILE"
    else
        printf -- 'Sudo : No \n' >>"$LOG_FILE"
        printf -- 'You can install the same from installing sudo from repository using apt, yum or zypper based on your distro. \n'
        exit 1
    fi

    if [[ "$FORCE" == "true" ]]; then
        printf -- 'Force attribute provided hence continuing with install without confirmation message\n' |& tee -a "$LOG_FILE"
    else
        # Ask user for prerequisite installation
        printf -- "\nAs part of the installation , dependencies would be installed/upgraded.\n"
        while true; do
            read -r -p "Do you want to continue (y/n) ? :  " yn
            case $yn in
            [Yy]*)
                printf -- 'User responded with Yes. \n' >>"$LOG_FILE"
                break
                ;;
            [Nn]*) exit ;;
            *) echo "Please provide confirmation to proceed." ;;
            esac
        done
    fi
}

function cleanup() {
    # Remove artifacts
    rm "$GOPATH/src/k8s.io/ingress-nginx/nginx_ingress_code_patch.diff"
    printf -- "Cleaned up the artifacts\n" >>"$LOG_FILE"
}

function configureAndInstall() {
    printf -- "Configuration and Installation started \n"


    if [[ "$ID" == "rhel" || "$ID" == "sles"  ]]; then

        #Install Go
        cd "$CURDIR"
        wget  $GO_INSTALL_URL 
        bash build_go.sh
        printf -- "Installed Go successfully\n" >> "$LOG_FILE"
    
    fi

   	# Set GOPATH if not already set
	if [[ -z "${GOPATH}" ]]; then
		printf -- "Setting default value for GOPATH \n"
		
        #Check if go directory exists
		if [ ! -d "$GO_DEFAULT" ]; then
			mkdir -p "$GO_DEFAULT"
		fi
		export GOPATH="$GO_DEFAULT"
        
	else
        export GOPATH="$GOPATH"
		printf -- "GOPATH already set : Value : %s \n" "$GOPATH" 
	fi

    #Download nginx-ingress-controller
    cd "$CURDIR"
    export DOCKER=docker
    mkdir -p $GOPATH/src/k8s.io/
    cd $GOPATH/src/k8s.io/
    git clone -b "nginx-${PACKAGE_VERSION}" https://github.com/kubernetes/ingress-nginx.git
    printf -- "Downloaded nginx-ingress-controller successfully\n"

    #Give permission to user
    sudo chown -R "$USER" "$GOPATH/src/k8s.io/ingress-nginx/"

    #Build NGINX Ingress Controller with the new image
    
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    # Add patches
    curl -o nginx_ingress_code_patch.diff $REPO_URL/nginx_ingress_code_patch.diff
    git apply "$GOPATH/src/k8s.io/ingress-nginx/nginx_ingress_code_patch.diff"
    printf -- "Patched source code successfully\n" 

    #Build nginx image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/nginx/"
    make container
    #Build e2e image for s390x
    cd "$GOPATH/src/k8s.io/ingress-nginx/images/e2e/"
    make docker-build

    #Build NGINX Ingress Controller with the new image
    cd "$GOPATH/src/k8s.io/ingress-nginx/"
    make build container
    printf -- "Built and installed nginx-ingress-controller successfully\n" 

    #Run Test
    runTest

    #cleanup
    cleanup

}

function runTest() {

    set +e
    if [[ "$TESTS" == "true" ]]; then
        printf -- 'Running tests \n\n' |& tee -a "$LOG_FILE"
        cd $GOPATH/src/k8s.io/ingress-nginx/
        make test
    fi

    set -e
}

function logDetails() {
    printf -- '**************************** SYSTEM DETAILS *************************************************************\n' >"$LOG_FILE"
    if [ -f "/etc/os-release" ]; then
        cat "/etc/os-release" >>"$LOG_FILE"
    fi

    cat /proc/version >>"$LOG_FILE"
    printf -- '*********************************************************************************************************\n' >>"$LOG_FILE"
    printf -- "Detected %s \n" "$PRETTY_NAME"
    printf -- "Request details : PACKAGE NAME= %s , VERSION= %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" |& tee -a "$LOG_FILE"
}

# Print the usage message
function printHelp() {
    echo
    echo "Usage: "
    echo " build_nginx-ingress-controller.sh  [-d debug] [-y install-without-confirmation] [-t install and run tests]"
    echo
}

while getopts "h?dyt" opt; do
    case "$opt" in
    h | \?)
        printHelp
        exit 0
        ;;
    d)
        set -x
        ;;
    y)
        FORCE="true"
        ;;
    t)
        TESTS="true"
        ;;
    esac
done

function gettingStarted() {
    printf -- '\n********************************************************************************************************\n'
    printf -- "* Getting Started * \n"
    printf -- "Deploying nginx-ingress-controller: \n\n"
    printf -- " cd \$GOPATH/src/k8s.io/ingress-nginx/ \n"
    printf -- " kubectl apply -f deploy/mandatory.yaml \n\n"
    printf -- "* Verify installed version * \n\n"
    printf -- " POD_NAMESPACE=ingress-nginx\n"
    printf -- " POD_NAME=\$(kubectl get pods --all-namespaces | grep nginx-ingress-controller | awk '{print \$2}') \n"
    printf -- " kubectl exec -it \$POD_NAME -n \$POD_NAMESPACE -- /nginx-ingress-controller --version \n"
    printf -- '\n********************************************************************************************************\n'
}

logDetails
prepare #Check Prequisites
DISTRO="$ID-$VERSION_ID"

case "$DISTRO" in
"ubuntu-16.04" | "ubuntu-18.04" | "ubuntu-19.04")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo apt-get update
    sudo apt-get install -y git make golang-1.10 curl  |& tee -a "$LOG_FILE"
    export PATH=/usr/lib/go-1.10/bin:$PATH
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"rhel-7.4" | "rhel-7.5" | "rhel-7.6")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo yum install -y git make curl  |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;
"sles-12.4" | "sles-15")
    printf -- "Installing %s %s for %s \n" "$PACKAGE_NAME" "$PACKAGE_VERSION" "$DISTRO" |& tee -a "$LOG_FILE"
    printf -- "Installing dependencies... it may take some time.\n"
    sudo zypper install -y git make curl |& tee -a "$LOG_FILE"
    configureAndInstall |& tee -a "$LOG_FILE"
    ;;

*)
    printf -- "%s not supported \n" "$DISTRO" |& tee -a "$LOG_FILE"
    exit 1
    ;;
esac

gettingStarted |& tee -a "$LOG_FILE"
