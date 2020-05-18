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
FINAL_DIR="${2}/Release_With_Kext_OCBuilder_Completed"

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
    mtoc_hash=$(curl -L "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.sha256") || exit 1

    if [ "${mtoc_hash}" = "" ]; then
      echo "Cannot obtain the latest compatible mtoc hash!"
      exit 1
    fi

    valid_mtoc=false
    if [ "$(which mtoc)" != "" ]; then
      mtoc_path=$(which mtoc)
      mtoc_hash_user=$(shasum -a 256 "${mtoc_path}" | cut -d' ' -f1)
      if [ "${mtoc_hash}" = "${mtoc_hash_user}" ]; then
        valid_mtoc=true
      elif [ "${IGNORE_MTOC_VERSION}" = "1" ]; then
        echo "Forcing the use of UNKNOWN mtoc version due to IGNORE_MTOC_VERSION=1"
        valid_mtoc=true
      elif [ "${mtoc_path}" != "/usr/local/bin/mtoc" ]; then
        echo "Custom UNKNOWN mtoc is installed to ${mtoc_path}!"
        echo "Hint: Remove this mtoc or use IGNORE_MTOC_VERSION=1 at your own risk."
        exit 1
      else
        echo "Found incompatible mtoc installed to ${mtoc_path}!"
        echo "Expected SHA-256: ${mtoc_hash}"
        echo "Found SHA-256:    ${mtoc_hash_user}"
        echo "Hint: Reinstall this mtoc or use IGNORE_MTOC_VERSION=1 at your own risk."
      fi
    fi

    if ! $valid_mtoc; then
      echo "Installing prebuilt mtoc automatically..."
      pushd /tmp >/dev/null
      rm -f mtoc mtoc-mac64.zip
      curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/mtoc-mac64.zip" || exit 1
      mtoczip=$(cat mtoc-mac64.zip)
      rm -rf mtoc-*
      curl -OL "https://github.com/acidanthera/ocbuild/raw/master/external/${mtoczip}" || exit 1
      unzip -q "${mtoczip}" mtoc || exit 1
      sudo rm -f /usr/local/bin/mtoc /usr/local/bin/mtoc.NEW || exit 1
      sudo cp mtoc /usr/local/bin/mtoc || exit 1
      popd >/dev/null

      mtoc_path=$(which mtoc)
      mtoc_hash_user=$(shasum -a 256 "${mtoc_path}" | cut -d' ' -f1)
      if [ "${mtoc_hash}" != "${mtoc_hash_user}" ]; then
        echo "Failed to install a compatible version of mtoc!"
        echo "Expected SHA-256: ${mtoc_hash}"
        echo "Found SHA-256:    ${mtoc_hash_user}"
        exit 1
      fi
    fi
}

buildamdsmc() {
  xcodebuild -target SMCAMDProcessor -configuration Release  >/dev/null || exit 1
  xcodebuild -target AMDRyzenCPUPowerManagement -configuration Release >/dev/null || exit 1
}

buildrelease() {
  xcodebuild -configuration Release  >/dev/null || exit 1
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
  mkdir -p tmp/EFI/BOOT || exit 1
  mkdir -p tmp/EFI/OC/ACPI || exit 1
  mkdir -p tmp/EFI/OC/Bootstrap || exit 1
  mkdir -p tmp/EFI/OC/Drivers || exit 1
  mkdir -p tmp/EFI/OC/Kexts || exit 1
  mkdir -p tmp/EFI/OC/Tools || exit 1
  mkdir -p tmp/EFI/OC/Resources/Audio || exit 1
  mkdir -p tmp/EFI/OC/Resources/Font || exit 1
  mkdir -p tmp/EFI/OC/Resources/Image || exit 1
  mkdir -p tmp/EFI/OC/Resources/Label || exit 1
  mkdir -p tmp/Docs/AcpiSamples || exit 1
  mkdir -p tmp/Utilities || exit 1
  # Mark binaries to be recognisable by OcBootManagementLib.
  dd if="${selfdir}/Library/OcBootManagementLib/BootSignature.bin" \
     of=BOOTx64.efi seek=64 bs=1 count=64 conv=notrunc || exit 1
  dd if="${selfdir}/Library/OcBootManagementLib/BootSignature.bin" \
     of=OpenCore.efi seek=64 bs=1 count=64 conv=notrunc || exit 1
  cp BootKicker.efi tmp/EFI/OC/Tools/ || exit 1
  cp BOOTx64.efi tmp/EFI/BOOT/ || exit 1
  cp BOOTx64.efi tmp/EFI/OC/Bootstrap/Bootstrap.efi || exit 1
  cp ChipTune.efi tmp/EFI/OC/Tools/ || exit 1
  cp CleanNvram.efi tmp/EFI/OC/Tools/ || exit 1
  cp GopStop.efi tmp/EFI/OC/Tools/ || exit 1
  cp HdaCodecDump.efi tmp/EFI/OC/Tools/ || exit 1
  cp HiiDatabase.efi tmp/EFI/OC/Drivers/ || exit 1
  cp KeyTester.efi tmp/EFI/OC/Tools/ || exit 1
  cp MmapDump.efi tmp/EFI/OC/Tools/ || exit 1
  cp ResetSystem.efi tmp/EFI/OC/Tools || exit 1
  cp RtcRw.efi tmp/EFI/OC/Tools || exit 1
  cp NvmExpressDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp AudioDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp OpenCanopy.efi tmp/EFI/OC/Drivers/ || exit 1
  cp OpenControl.efi tmp/EFI/OC/Tools/ || exit 1
  cp OpenCore.efi tmp/EFI/OC/ || exit 1
  cp OpenRuntime.efi tmp/EFI/OC/Drivers/ || exit 1
  cp OpenUsbKbDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp Ps2MouseDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp UsbMouseDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp Shell.efi tmp/EFI/OC/Tools/OpenShell.efi || exit 1
  cp VerifyMsrE2.efi tmp/EFI/OC/Tools/ || exit 1
  cp XhciDxe.efi tmp/EFI/OC/Drivers/ || exit 1
  cp "${selfdir}/Docs/Configuration.pdf" tmp/Docs/ || exit 1
  cp "${selfdir}/Docs/Differences/Differences.pdf" tmp/Docs/ || exit 1
  cp "${selfdir}/Docs/Sample.plist" tmp/Docs/ || exit 1
  cp "${selfdir}/Docs/SampleFull.plist" tmp/Docs/ || exit 1
  cp "${selfdir}/Changelog.md" tmp/Docs/ || exit 1
  cp -r "${selfdir}/Docs/AcpiSamples/" tmp/Docs/AcpiSamples/ || exit 1
  cp -r "${selfdir}/Utilities/LegacyBoot" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/CreateVault" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/LogoutHook" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/macrecovery" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/disklabel/disklabel" tmp/Utilities/ || exit 1
  cp -r "${selfdir}/Utilities/icnspack/icnspack" tmp/Utilities/ || exit 1
  pushd tmp || exit 1
  zip -qry -FS ../"OpenCore-${ver}-${2}.zip" * || exit 1
  popd || exit 1
  rm -rf tmp || exit 1
  popd || exit 1
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
  cp "${BUILD_DIR}"/OpenCorePkg/Binaries/RELEASE/*.zip "${FINAL_DIR}/"
  cd "${FINAL_DIR}/"
  unzip *.zip  >/dev/null || exit 1
  rm -rf *.zip
  cp -r "${BUILD_DIR}/Lilu/build/Release/Lilu.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/AppleALC/build/Release/AppleALC.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}"/VirtualSMC/build/Release/*.kext "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/WhateverGreen/build/Release/WhateverGreen.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/AirportBrcmFixup/build/Release/AirportBrcmFixup.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/SMCAMDProcessor/build/Release/SMCAMDProcessor.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/SMCAMDProcessor/build/Release/AMDRyzenCPUPowerManagement.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/AtherosE2200Ethernet/build/Release/AtherosE2200Ethernet.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/IntelMausi/build/Release/IntelMausi.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/RTL8111_driver_for_OS_X/build/Release/RealtekRTL8111.kext" "${FINAL_DIR}"/EFI/OC/Kexts
  cp -r "${BUILD_DIR}/NVMeFix/build/Release/NVMeFix.kext" "${FINAL_DIR}"/EFI/OC/Kexts
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
sleep 1
echo "Compiling the latest commited Release version of Lilu..."
buildrelease
echo "Lilu Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning AppleALC repo..."
git clone https://github.com/acidanthera/AppleALC.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/AppleALC"
cd "${BUILD_DIR}/AppleALC"
echo "Compiling the latest commited Release version of AppleALC..."
buildrelease
echo "AppleALC Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning WhateverGreen repo..."
git clone https://github.com/acidanthera/WhateverGreen.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/WhateverGreen"
cd "${BUILD_DIR}/WhateverGreen"
echo "Compiling the latest commited Release version of WhateverGreen..."
buildrelease
echo "WhateverGreen Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning VirtualSMC repo..."
git clone https://github.com/acidanthera/VirtualSMC.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/VirtualSMC"
cd "${BUILD_DIR}/VirtualSMC"
echo "Compiling the latest commited Debug version of VirtualSMC..."
builddebug
echo "VirtualSMC Debug Completed..."
sleep 1
echo "Compiling the latest commited Release version of VirtualSMC..."
buildrelease
echo "VirtualSMC Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning AirportBrcmFixup repo..."
git clone https://github.com/acidanthera/AirportBrcmFixup.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/AirportBrcmFixup"
cd "${BUILD_DIR}/AirportBrcmFixup"
echo "Compiling the latest commited Release version of AirportBrcmFixup..."
buildrelease
echo "AirportBrcmFixup Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning AtherosE2200Ethernet repo..."
git clone https://github.com/Mieze/AtherosE2200Ethernet.git >/dev/null || exit 1
cd "${BUILD_DIR}/AtherosE2200Ethernet"
echo "Compiling the latest commited Release version of AtherosE2200Ethernet..."
buildrelease
echo "AtherosE2200Ethernet Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning IntelMausi repo..."
git clone https://github.com/acidanthera/IntelMausi.git >/dev/null || exit 1
cd "${BUILD_DIR}/IntelMausi"
echo "Compiling the latest commited Release version of IntelMausi..."
buildrelease
echo "IntelMausi Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning RealtekRTL8111 repo..."
git clone https://github.com/Mieze/RTL8111_driver_for_OS_X.git >/dev/null || exit 1
cd "${BUILD_DIR}/RTL8111_driver_for_OS_X"
echo "Compiling the latest commited Release version of RealtekRTL8111..."
buildrelease
echo "RealtekRTL8111 Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning SMCAMDProcessor repo..."
git clone https://github.com/trulyspinach/SMCAMDProcessor.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/SMCAMDProcessor"
cp -r "${BUILD_DIR}/VirtualSMC/build/Debug/VirtualSMC.kext" "${BUILD_DIR}/SMCAMDProcessor"
cd "${BUILD_DIR}/SMCAMDProcessor"
echo "Compiling the latest commited Release version of SMCAMDProcessor..."
buildamdsmc
echo "SMCAMDProcessor Release Completed..."

cd "${BUILD_DIR}"

echo "Cloning NVMeFix repo..."
git clone https://github.com/acidanthera/NVMeFix.git >/dev/null || exit 1
cp -r "${BUILD_DIR}/Lilu/build/Debug/Lilu.kext" "${BUILD_DIR}/NVMeFix"
cd "${BUILD_DIR}/NVMeFix"
echo "Compiling the latest commited Release version of NVMeFix..."
buildrelease
echo "NVMeFix Release Completed..."

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
ln -s ../UDK/Build/OpenCorePkg/RELEASE_XCODE5/X64 RELEASE
cd ..
opencoreudkclone
cd UDK
ln -s .. OpenCorePkg
make -C BaseTools >/dev/null || exit 1
sleep 1
export NASM_PREFIX=/usr/local/bin/
source edksetup.sh --reconfig >/dev/null
sleep 1
echo "Compiling the latest commited Release version of OpenCorePkg..."
build -a X64 -b RELEASE -t XCODE5 -p OpenCorePkg/OpenCorePkg.dsc >/dev/null || exit 1

cd .. >/dev/null || exit 1
opencorepackage "Binaries/RELEASE" "RELEASE" >/dev/null || exit 1

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

ocbinarydataclone

if [ ! -d "${FINAL_DIR}" ]; then
  mkdir -p "${FINAL_DIR}"
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
  open -a Safari https://dortania.github.io/OpenCore-Desktop-Guide/
else
  rm -rf "${FINAL_DIR}"/*
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
  open -a Safari https://dortania.github.io/OpenCore-Desktop-Guide/
fi
