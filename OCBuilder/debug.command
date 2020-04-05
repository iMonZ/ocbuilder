#!/bin/bash

prompt() {
    dialogTitle="OCBuilder"
    authPass=$(/usr/bin/osascript <<EOT
        tell application "System Events"
            activate
            repeat
                display dialog "This application requires administrator privileges. Please enter your administrator account password below to continue:" ¬
                    default answer "" ¬
                    with title "$dialogTitle" ¬
                    with hidden answer ¬
                    buttons {"Quit", "Continue"} default button 2
                if button returned of the result is "Quit" then
                    return 1
                    exit repeat
                else if the button returned of the result is "Continue" then
                    set pswd to text returned of the result
                    set usr to short user name of (system info)
                    try
                        do shell script "echo test" user name usr password pswd with administrator privileges
                        return pswd
                        exit repeat
                    end try
                end if
            end repeat
        end tell
    EOT
    )

    if [ "$authPass" == 1 ]
    then
        /bin/echo "User aborted. Exiting..."
        exit 0
    fi

    sudo () {
        /bin/echo $authPass | /usr/bin/sudo -S "$@"
    }
}

BUILD_DIR="${1}/OCBuilder_Clone"
FINAL_DIR="${2}/Debug_With_Kext_OCBuilder_Completed"

installnasm () {
    pushd /tmp >/dev/null
    rm -rf nasm-mac64.zip
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/nasm-mac64.zip" || exit 1
    nasmzip=$(cat nasm-mac64.zip)
    rm -rf nasm-*
    curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${nasmzip}" || exit 1
    unzip -q "${nasmzip}" nasm*/nasm nasm*/ndisasm || exit 1
    if [ -d /usr/local/bin ]; then
        sudo mv nasm*/nasm /usr/local/bin/ || exit 1
        sudo mv nasm*/ndisasm /usr/local/bin/ || exit 1
        rm -rf "${nasmzip}" nasm-*
    else
        sudo mkdir -p /usr/local/bin || exit 1
        sudo mv nasm*/nasm /usr/local/bin/ || exit 1
        sudo mv nasm*/ndisasm /usr/local/bin/ || exit 1
        rm -rf "${nasmzip}" nasm-*
    fi
}

installmtoc () {
    CCTOOLS_VERSION=949.0.1
    CCTOOLS_NAME=cctools-${CCTOOLS_VERSION}
    CCTOOLS_ARCHIVE=${CCTOOLS_NAME}.tar.gz
    CCTOOLS_LINK=https://opensource.apple.com/tarballs/cctools/${CCTOOLS_ARCHIVE}
    MTOC_ARCHIVE="mtoc-${CCTOOLS_VERSION}-macosx.zip"
    MTOC_LATEST_ARCHIVE="mtoc-mac64.zip"
    curl -OL "${CCTOOLS_LINK}"                               || abort "Cannot download cctools from ${CCTOOLS_LINK}"
    tar -xf "${CCTOOLS_ARCHIVE}"                             || abort "Cannot extract cctools ${CCTOOLS_ARCHIVE}"
    cd "${CCTOOLS_DIR}"                                      || abort "Cannot switch to cctools dir ${CCTOOLS_DIR}"
    patch -p1 < "${SRC_DIR}/patches/mtoc-permissions.patch"  || abort "Cannot apply mtoc-permissions.patch"
    make LTO= EFITOOLS=efitools -C libstuff                  || abort "Cannot build libstuff"
    make -C efitools                                         || abort "Cannot build efitools"
    strip -x "${CCTOOLS_DIR}/efitools/mtoc.NEW"              || abort "Cannot strip mtoc"
    mkdir "${DIST_DIR}"                                      || abort "Cannot create dist dir ${DIST_DIR}"
    cd "${DIST_DIR}"                                         || abort "Cannot switch to dist dir ${DIST_DIR}"
    cp "${CCTOOLS_DIR}/efitools/mtoc.NEW" "${DIST_DIR}/mtoc" || abort "Cannot copy mtoc to ${DIST_DIR}"
    zip -qry "${SRC_DIR}/external/${MTOC_ARCHIVE}" mtoc      || abort "Cannot archive mtoc into ${MTOC_ARCHIVE}"
    cd "${SRC_DIR}/external"                                 || abort "Cannot switch to ${SRC_DIR}/external"
    ln -s "${MTOC_ARCHIVE}" "${MTOC_LATEST_ARCHIVE}"         || abort "Cannot update ${MTOC_LATEST_ARCHIVE} symlink"
    openssl sha256 "${DIST_DIR}/mtoc" | cut -d' ' -f2 > "${SRC_DIR}/external/${MTOC_LATEST_HASH}" || abort "Cannot update hash"
    sudo cp "${DIST_DIR}/mtoc" "/usr/local/bin/mtoc"         || abort "Cannot update /usr/local/bin/mtoc"
    quit 0
}


builddebug() {
  xcodebuild -configuration Debug  >/dev/null || exit 1
}

applesupportpackage() {
  pushd "$1" || exit 1
  rm -rf tmp || exit 1
  mkdir -p tmp/Drivers || exit 1
  mkdir -p tmp/Tools   || exit 1
  cp AudioDxe.efi tmp/Drivers/          || exit 1
  cp ApfsDriverLoader.efi tmp/Drivers/  || exit 1
  cp VBoxHfs.efi tmp/Drivers/           || exit 1
  pushd tmp || exit 1
  zip -qry -FS ../"AppleSupport-${ver}-${2}.zip" * || exit 1
  popd || exit 1
  rm -rf tmp || exit 1
  popd || exit 1
}

opencorepackage() {
  selfdir=$(pwd)
  pushd "$1" || exit 1
  rm -rf tmp || exit 1
  mkdir -p tmp/EFI || exit 1
  mkdir -p tmp/EFI/OC || exit 1
  mkdir -p tmp/EFI/OC/ACPI || exit 1
  mkdir -p tmp/EFI/OC/Drivers || exit 1
  mkdir -p tmp/EFI/OC/Kexts || exit 1
  mkdir -p tmp/EFI/OC/Tools || exit 1
  mkdir -p tmp/EFI/BOOT || exit 1
  mkdir -p tmp/Docs/AcpiSamples || exit 1
  mkdir -p tmp/Utilities || exit 1
  cp BootKicker.efi tmp/EFI/OC/Tools/ || exit 1
  cp BOOTx64.efi tmp/EFI/BOOT/ || exit 1
  cp ChipTune.efi tmp/EFI/OC/Tools/ || exit 1
  cp CleanNvram.efi tmp/EFI/OC/Tools/ || exit 1
  cp GopStop.efi tmp/EFI/OC/Tools/ || exit 1
  cp HdaCodecDump.efi tmp/EFI/OC/Tools/ || exit 1
  cp HiiDatabase.efi tmp/EFI/OC/Drivers/ || exit 1
  cp KeyTester.efi tmp/EFI/OC/Tools/ || exit 1
  cp MmapDump.efi tmp/EFI/OC/Tools/ || exit 1
  cp NvmExpressDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp OpenCanopy.efi tmp/EFI/OC/Drivers/ || exit 1
  cp OpenControl.efi tmp/EFI/OC/Tools/ || exit 1
  cp OpenCore.efi tmp/EFI/OC/ || exit 1
  cp OpenRuntime.efi tmp/EFI/OC/Drivers/ || exit 1
  cp OpenUsbKbDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp Shell.efi tmp/EFI/OC/Tools/OpenShell.efi || exit 1
  cp VerifyMsrE2.efi tmp/EFI/OC/Tools/ || exit 1
  cp XhciDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp "${selfdir}/Docs/Configuration.pdf" tmp/Docs/ || exit 1
  cp "${selfdir}/Docs/Differences/Differences.pdf" tmp/Docs/ || exit 1
  cp "${selfdir}/Docs/Sample.plist" tmp/Docs/ || exit 1
  cp "${selfdir}/Docs/SampleFull.plist" tmp/Docs/ || exit 1
  cp "${selfdir}/Changelog.md" tmp/Docs/ || exit 1
  cp -r "${selfdir}/Docs/AcpiSamples/" tmp/Docs/AcpiSamples/ || exit 1
  cp -r "${selfdir}/Utilities/BootInstall" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/CreateVault" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/LogoutHook" tmp/Utilities/ || exit 1
  pushd tmp || exit 1
  zip -qry -FS ../"OpenCore-${ver}-${2}.zip" * || exit 1
  popd || exit 1
  rm -rf tmp || exit 1
  popd || exit 1
}

applesupportpkgclone() {
  echo "Cloning AppleSupportPkg SupportPkgs into AUDK..."
  git clone -q https://github.com/acidanthera/EfiPkg EfiPkg -b master --depth=1
  git clone -q https://github.com/acidanthera/OpenCorePkg OpenCorePkg -b master --depth=1
}

applesupportudkclone() {
  echo "Cloning AUDK Repo into AppleSupportPkg..."
  git clone -q https://github.com/acidanthera/audk UDK -b master --depth=1
}

applesupportclone() {
  echo "Cloning AppleSupportPkg Git repo..."
  git clone -q https://github.com/acidanthera/AppleSupportPkg.git
}

opencorepkgclone() {
  echo "Cloning OpenCorePkg SupportPkgs into AUDK..."
  git clone -q https://github.com/acidanthera/EfiPkg EfiPkg -b master --depth=1
  git clone -q https://github.com/acidanthera/MacInfoPkg MacInfoPkg -b master --depth=1
}

opencoreudkclone() {
  echo "Cloning AUDK Repo into OpenCorePkg..."
  git clone -q https://github.com/acidanthera/audk UDK -b master --depth=1
}

opencoreclone() {
  echo "Cloning OpenCorePkg Git repo..."
  git clone -q https://github.com/acidanthera/OpenCorePkg.git
}

ocbinarydataclone () {
  echo "Cloning OcBinaryData Git repo..."
  git clone -q https://github.com/acidanthera/OcBinaryData.git
}

copyBuildProducts() {
  echo "Copying compiled products into EFI Structure folder in ${FINAL_DIR}..."
  cp "${BUILD_DIR}"/OpenCorePkg/Binaries/DEBUG/*.zip "${FINAL_DIR}/"
  cd "${FINAL_DIR}/"
  unzip *.zip  >/dev/null || exit 1
  rm -rf *.zip
  cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/AppleALC/build/Debug/AppleALC.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}"/VirtualSMC/build/Debug/*.kext "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/WhateverGreen/build/Debug/WhateverGreen.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/AirportBrcmFixup/build/Debug/AirportBrcmFixup.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/MacProMemoryNotificationDisabler/build/Debug/MacProMemoryNotificationDisabler.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/AtherosE2200Ethernet/build/Debug/AtherosE2200Ethernet.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/SMCAMDProcessor/build/Debug/SMCAMDProcessor.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/RTL8111_driver_for_OS_X/build/Debug/RealtekRTL8111.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/NVMeFix/build/Debug/NVMeFix.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cd "${BUILD_DIR}"/AppleSupportPkg/Binaries/DEBUG
  rm -rf "${BUILD_DIR}"/AppleSupportPkg/Binaries/DEBUG/Drivers
  rm -rf "${BUILD_DIR}"/AppleSupportPkg/Binaries/DEBUG/Tools
  unzip *.zip  >/dev/null || exit 1
  cp -r "${BUILD_DIR}"/AppleSupportPkg/Binaries/DEBUG/Drivers/*.efi "${FINAL_DIR}"/EFI/OC/Drivers
  cp -r "${BUILD_DIR}"/OcBinaryData/Resources "${FINAL_DIR}"/EFI/OC/
  cp -r "${BUILD_DIR}"/OcBinaryData/Drivers/*.efi "${FINAL_DIR}"/EFI/OC/Drivers
  echo "All Done!..."
}

PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

if [ ! -d "${BUILD_DIR}" ]; then
  mkdir -p "${BUILD_DIR}"
else
  rm -rf "${BUILD_DIR}/"
  mkdir -p "${BUILD_DIR}"
fi

cd "${BUILD_DIR}"

echo "Cloning Lilu repo..."
git clone https://github.com/acidanthera/Lilu.git >/dev/null || exit 1
cd "${BUILD_DIR}/Lilu"
echo "Compiling the latest commited Debug version of Lilu..."
builddebug
echo "Lilu Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning AppleALC repo..."
git clone https://github.com/acidanthera/AppleALC.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/AppleALC"
cd "${BUILD_DIR}/AppleALC"
echo "Compiling the latest commited Debug version of AppleALC..."
builddebug
echo "AppleALC Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning WhateverGreen repo..."
git clone https://github.com/acidanthera/WhateverGreen.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/WhateverGreen"
cd "${BUILD_DIR}/WhateverGreen"
echo "Compiling the latest commited Debug version of WhateverGreen..."
builddebug
echo "WhateverGreen Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning VirtualSMC repo..."
git clone https://github.com/acidanthera/VirtualSMC.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/VirtualSMC"
cd "${BUILD_DIR}/VirtualSMC"
echo "Compiling the latest commited Debug version of VirtualSMC..."
builddebug
echo "VirtualSMC Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning AirportBrcmFixup repo..."
git clone https://github.com/acidanthera/AirportBrcmFixup.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/AirportBrcmFixup"
cd "${BUILD_DIR}/AirportBrcmFixup"
echo "Compiling the latest commited Debug version of AirportBrcmFixup..."
builddebug
echo "AirportBrcmFixup Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning MacProMemoryNotificationDisabler repo..."
git clone https://github.com/IOIIIO/MacProMemoryNotificationDisabler.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/MacProMemoryNotificationDisabler"
cd "${BUILD_DIR}/MacProMemoryNotificationDisabler"
echo "Compiling the latest commited Debug version of MacProMemoryNotificationDisabler..."
builddebug
echo "MacProMemoryNotificationDisabler Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning AtherosE2200Ethernet repo..."
git clone https://github.com/Mieze/AtherosE2200Ethernet.git >/dev/null || exit 1
cd "${BUILD_DIR}/AtherosE2200Ethernet"
echo "Compiling the latest commited Debug version of AtherosE2200Ethernet..."
builddebug
echo "AtherosE2200Ethernet Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning RealtekRTL8111 repo..."
git clone https://github.com/Mieze/RTL8111_driver_for_OS_X.git >/dev/null || exit 1
cd "${BUILD_DIR}/RTL8111_driver_for_OS_X"
echo "Compiling the latest commited Debug version of RealtekRTL8111..."
builddebug
echo "RealtekRTL8111 Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning SMCAMDProcessor repo..."
git clone https://github.com/trulyspinach/SMCAMDProcessor.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/SMCAMDProcessor"
cp -r "${BUILD_DIR}/VirtualSMC/build/Debug/VirtualSMC.kext" "${BUILD_DIR}/SMCAMDProcessor"
cd "${BUILD_DIR}/SMCAMDProcessor"
echo "Compiling the latest commited Debug version of SMCAMDProcessor..."
builddebug
echo "SMCAMDProcessor Debug Completed..."

cd "${BUILD_DIR}"

echo "Cloning NVMeFix repo..."
git clone https://github.com/acidanthera/NVMeFix.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/NVMeFix"
cd "${BUILD_DIR}/NVMeFix"
echo "Compiling the latest commited Debug version of NVMeFix..."
builddebug
echo "NVMeFix Debug Completed..."

cd "${BUILD_DIR}"

if [ "$(nasm -v)" = "" ]; then
    echo "NASM is missing!, installing..."
    prompt
    installnasm
else
    echo "NASM Already Installed..."
fi

if [ "$(which mtoc)" == "" ]; then
    echo "MTOC is missing!, installing..."
    prompt
    installmtoc
else
    echo "MTOC Already Installed..."
fi

cd "${BUILD_DIR}"

opencoreclone
unset WORKSPACE
unset PACKAGES_PATH
cd "${BUILD_DIR}/OpenCorePkg"
mkdir Binaries
cd Binaries
ln -s ../UDK/Build/OpenCorePkg/DEBUG_XCODE5/X64 DEBUG
cd ..
opencoreudkclone
cd UDK
opencorepkgclone
ln -s .. OpenCorePkg
make -C BaseTools >/dev/null || exit 1
sleep 1
export NASM_PREFIX=/usr/local/bin/
source edksetup.sh --reconfig >/dev/null
sleep 1
echo "Compiling the latest commited Debug version of OpenCorePkg..."
build -a X64 -b DEBUG -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc >/dev/null || exit 1

cd .. >/dev/null || exit 1
opencorepackage "Binaries/DEBUG" "DEBUG" >/dev/null || exit 1

if [ "$BUILD_UTILITIES" = "1" ]; then
  UTILS=(
    "AppleEfiSignTool"
    "EfiResTool"
    "disklabel"
    "RsaTool"
  )

  cd Utilities || exit 1
  for util in "${UTILS[@]}"; do
    cd "$util" || exit 1
    make || exit 1
    cd - || exit 1
  done
fi

cd "${BUILD_DIR}"/OpenCorePkg/Library/OcConfigurationLib || exit 1
./CheckSchema.py OcConfigurationLib.c >/dev/null || exit 1

cd "${BUILD_DIR}"

applesupportclone
unset WORKSPACE
unset PACKAGES_PATH
cd "${BUILD_DIR}/AppleSupportPkg"
mkdir Binaries >/dev/null || exit 1
cd Binaries >/dev/null || exit 1
ln -s ../UDK/Build/AppleSupportPkg/DEBUG_XCODE5/X64 DEBUG >/dev/null || exit 1
cd .. >/dev/null || exit 1
applesupportudkclone
cd UDK
applesupportpkgclone
ln -s .. AppleSupportPkg >/dev/null || exit 1
make -C BaseTools >/dev/null || exit 1
sleep 1
unset WORKSPACE
unset EDK_TOOLS_PATH
export NASM_PREFIX=/usr/local/bin/
source edksetup.sh --reconfig >/dev/null || exit 1
sleep 1
echo "Compiling the latest commited Debug version of AppleSupportPkg..."
build -a X64 -b DEBUG -t XCODE5 -p AppleSupportPkg/AppleSupportPkg.dsc >/dev/null || exit 1

cd .. >/dev/null || exit 1
applesupportpackage "Binaries/DEBUG" "DEBUG" >/dev/null || exit 1

cd "${BUILD_DIR}"

ocbinarydataclone

if [ ! -d "${FINAL_DIR}" ]; then
  mkdir -p "${FINAL_DIR}"
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
  open -a Safari https://khronokernel.github.io/Opencore-Vanilla-Desktop-Guide/
else
  rm -rf "${FINAL_DIR}"/*
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
  open -a Safari https://khronokernel.github.io/Opencore-Vanilla-Desktop-Guide/
fi

