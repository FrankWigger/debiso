#!/bin/bash
set -e

# Initialize our own variables
output_file="debiso-output.iso"
envfile=""
isoFile=""
preseedFile=""
override=false
dryrun=false


checkRequiredPrograms() {
  # Check for required programs
  if ! [ -x "$(command -v bsdtar)" ]; then
    echo "Error: bsdtar is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v genisoimage)" ]; then
    echo "Error: genisoimage is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v isohybrid)" ]; then
    echo "Error: isohybrid is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v envsubst)" ]; then
    echo "Error: envsubst is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v cpio)" ]; then
    echo "Error: cpio is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v realpath)" ]; then
    echo "Error: realpath is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v md5sum)" ]; then
    echo "Error: md5sum is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v gunzip)" ]; then
    echo "Error: gunzip is not installed." >&2
    exit 1
  fi

  if ! [ -x "$(command -v gzip)" ]; then
    echo "Error: gzip is not installed." >&2
    exit 1
  fi
}

printSettings() {
  # Print variables
  echo "------------------- General Settings -------------------"
  echo "Hostname: $HOSTNAME" 
  echo "Domain: $DOMAIN"
  echo "Timezone: $TIMEZONE"
  echo "Locale: $LOCALE"
  echo "Keymap: $KEYMAP"
  echo "Mirror: $MIRROR"
  
  echo "------------------- Root Settings -------------------"
  echo "Root Enable: $ROOT_ENABLE"
  echo "Root Allow SSH: $ROOT_ALLOWSSH"

  echo "------------------- Account Settings -------------------"
  echo "User Fullname: $USER_FULLNAME"
  echo "User Name: $USER_NAME"
  
  echo "------------------- Network Settings -------------------"
  echo "Network Interface: $NET_INTERFACE"
}

createIso() {
  # Create temporary directory
  TMPDIR=$(mktemp -d)
  cd $TMPDIR
  # Replace variables in preseed file
  envsubst < $preseedFile > preseed.cfg

  if [ $DEBIAN_ROOT_ALLOWSSH = true ]; then
    echo "Enabling root ssh"
    echo "" >> preseed.cfg
    echo "d-i preseed/late_command string \
    in-target sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config" >> preseed.cfg
  fi
  
  # Untar iso to temporary directory
  echo "Extracting iso to $TMPDIR/iso"
  mkdir -p iso
  bsdtar -C iso -xf $isoFile 
  chmod -R +w iso
  cd iso

cat << EOF > isolinux/isolinux.cfg
DEFAULT install
LABEL install
  kernel /install.amd/vmlinuz
  append vga=788 initrd=/install.amd/initrd.gz --- quiet
EOF

  # Patch initrd
  echo "Patching initrd"
  gunzip install.amd/initrd.gz
  echo ../preseed.cfg | cpio -H newc -o -A -F install.amd/initrd
  gzip install.amd/initrd

  # Recreate md5sum.txt
  find ./ -type f -exec md5sum {} \; > md5sum.txt
  cd ..

  # Generate iso image
  echo "Generating iso image"
  genisoimage -V Debian-headless \
          -r -J -b isolinux/isolinux.bin -c isolinux/boot.cat \
          -no-emul-boot -boot-load-size 4 -boot-info-table \
          -o $output_file iso

  # fix MBR
  isohybrid $output_file

  #rm -r $TMPDIR

  echo "Done"
}


############################## Main ##############################

checkRequiredPrograms

# Parse command line arguments
while (( "$#" )); do
  case "$1" in
    -h|--help)
      exit 0
      ;;
    --overwrite)
      overwrite=true
      ;;
    --dryrun)
        dryrun=true
        ;;
    -e|--env)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        envfile=$2
        shift 
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -o|--output)
      if [ -n "$2" ] && [ ${2:0:1} != "-" ]; then
        output_file=$2
        shift 2
      else
        echo "Error: Argument for $1 is missing" >&2
        exit 1
      fi
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      ;;
  esac

  shift
done

# Set positional arguments in their proper place
eval set -- "$PARAMS"

# Check for missing arguments
if ! [ $# -eq 2 ]; then
    echo "Error: Missing arguments" >&2
    echo "Usage: $0 <iso file> <preseed file> [flags]" >&2
    exit 1
fi

# Set variables
isoFile=$1
preseedFile=$2

# Check for missing iso file
if ! [ -f "$isoFile" ]; then
    echo "Error: ISO file not found" >&2
    exit 1
fi

# Check for missing preseed file
if ! [ -f "$preseedFile" ]; then
    preseedFileDir=$(dirname "$preseedFile")
    if [ "$preseedFileDir" == "." ]; then
        if case $preseedFile in "./"*) true;; *) false;; esac; then
            echo "" > /dev/null
        else
            echo $preseedFile not locally found. Looking in /etc/debiso
            preseedFile="/etc/debiso/$preseedFile"
        fi
    fi
fi

if ! [ -f "$preseedFile" ]; then
    echo "Error: Preseed file not found" >&2
    exit 1
fi

if [ -z "$envfile" ] && [ -f ".env" ]; then
    envfile=".env"
fi

if [ -f $output_file ]; then
    if [ "$overwrite" = true ]; then
        echo "Overwriting output file"
        rm $output_file
    else
      echo "Error: Output file already exists" >&2
      exit 1
    fi
fi

# Set environment variables 
if [ -f "$envfile" ]; then
    echo "Loading environment variables from $envfile"
    set -o allexport
    . $envfile
    set +o allexport
else
    echo "Environment file $envfile not found"
    exit 1
fi

# Set variables
HOSTNAME="${DEBIAN_HOSTNAME:=unamendhost}"
DOMAIN="${DEBIAN_DOMAIN:=unnameddomain}"
TIMEZONE="${DEBIAN_TIMEZONE:=US/Eastern}"
MIRROR="${DEBIAN_MIRROR:-http.us.debian.org}"

ROOT_ENABLE="${DEBIAN_ROOT_ENABLE:=false}"
ROOT_PASSWORD="${DEBIAN_ROOT_PASSWORD:=r00tme}"
ROOT_ALLOWSSH="${DEBIAN_ROOT_ALLOWSSH:=false}"

USER_FULLNAME="${DEBIAN_USER_FULLNAME:=Full Name}"
USER_NAME="${DEBIAN_USER_NAME:-username}"
USER_PASSWORD="${DEBIAN_USER_PASSWORD:=p@ssw0rd}"

LOCALE="${DEBIAN_LOCALE:=en_US}"
KEYMAP="${DEBIAN_KEYMAP:=us}"

NET_INTERFACE="${DEBIAN_NET_INTERFACE:=auto}"

printSettings

if ! [ "$dryrun" = true ]; then
    preseedFile=$(realpath $preseedFile)
    output_file=$(realpath $output_file)
    isoFile=$(realpath $isoFile)
    createIso
fi

