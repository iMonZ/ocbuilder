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
FINAL_DIR="${2}/Debug_Without_Kext_OCBuilder_Completed"

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
  if [ -d "{selfdir}/Utilities/macserial/bin" ]; then
    cp -r "${selfdir}/Utilities/macserial/bin" tmp/Utilities/macserial || exit 1
  else
    mkdir -p tmp/Utilities/macserial || exit 1
  fi
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
  cp "${BUILD_DIR}"/OpenCorePkg/Binaries/DEBUG/*.zip "${FINAL_DIR}/"
  cd "${FINAL_DIR}/"
  unzip *.zip  >/dev/null || exit 1
  rm -rf *.zip
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

ocbinarydataclone

if [ ! -d "${FINAL_DIR}" ]; then
  mkdir -p "${FINAL_DIR}"
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
else
  rm -rf "${FINAL_DIR}"/*
  copyBuildProducts
#  rm -rf "${BUILD_DIR}/"
fi


