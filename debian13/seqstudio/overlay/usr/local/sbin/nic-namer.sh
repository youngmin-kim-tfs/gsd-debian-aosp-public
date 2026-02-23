#!/bin/bash

# Predefined names
IFACE_4=("ext0" "int1" "int0" "ext1")
IFACE_3=("ext0" "int0" "ext1")
IFACE_2=("ext1" "ext0")
IFACE_1=("ext0")

# Get a sorted list of PCI paths
pci_list=()
for d in /sys/class/net/*; do
    iface="$(basename ${d})"
    type=$(cat ${d}/type)

    [[ ${iface} == "lo" ]] && continue
    [[ ! -e ${d}/device ]] && continue
    [[ -d ${d}/wireless ]] && continue
    [[ $type != "1" ]] && continue

    dev_path="$(readlink -f "${d}/device" 2>/dev/null || true)"
    [[ -z ${dev_path} ]] && continue

    pci_list+=("pci-$(basename ${dev_path})")
done
mapfile -t pci_sorted < <(printf '%s\n' "${pci_list[@]}" | sort)

# Select the predefined name
count=${#pci_sorted[@]}
if (( $count <= 4 )); then
    case $count in
        1) names=("${IFACE_1[@]}") ;;
        2) names=("${IFACE_2[@]}") ;;
        3) names=("${IFACE_3[@]}") ;;
        4) names=("${IFACE_4[@]}") ;;
    esac
fi

# Generate *.link in /etc/systemd/network
for ((i=0; i<$count; i++)); do
    (( $i > 4 )) && continue

    seq=$((i + 10))
    file="/etc/systemd/network/$seq-persistent-net.link"
    rm -f "${file}"
    cat <<EOF > "${file}"
[Match]
Path=${pci_sorted[i]}

[Link]
Name=${names[i]}
EOF

done