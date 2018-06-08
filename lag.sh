#!/usr/bin/env bash

##################################################################################################
# Script Name: lag.sh
# Description: Creates bond interfaces from batch mode or user input 
# Args: ./lag.sh [-c | -r <bond_interface_name> | -l | -m <bond_interface_name>] \
#       -b 'bond_mode' -i "first_int_name,second_int_name,.." -o "Additional Optional Bonding Options"
# Author: rhythmicsoul
# Date: 2018/05/28
# Version: 0.1
# Bash Version: GNU bash, version 4.2.46(2)-release (x86_64-redhat-linux-gnu)
# Notes: This script must be executed as root user otherwise an error is thrown
##################################################################################################


##################################################################################################
# Display the Usage of the script
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
##################################################################################################
displayUsage(){
    cat << DISPLAY_HELP
Usage: $0  [-c | -r <bond_interface_name> | -l | -m <bond_interface_name>] -b 'bond_mode' -i "first_int_name,second_int_name,..." -o "Additional Optional Bonding Options"

OPTIONS
    -c       Create bond"
    -r       Remove bond. Usage -r <bond_interface_name>
    -l       Display the status of the NICs
    -m       Modify the bond configuration. Usage -m <bond_interface_name> -o"<Manual Bonding Options>" -b "<Bonding_Modes>"
    -k       Add all the availabe interfaces to a single bond.
    -b       Bond modes, numeric and key values are supported. This is a mandatory parameter. Usage -b "<0|balance-rr>"
    -i       Physical Interfaces to use in the bond. Minum of two physical interfaces are required. This is a mandatory parameter. Usage -i "enp0s1,enp0s2,enp0s3...."
    -o       BONDING_OPTS in the bond interface configuration. If this is passed the default values will be overwritten with the options provided here. This is optional. Usage -o "miimon 200"
DISPLAY_HELP
    exit 0
}

##################################################################################################
# Loads the bonding module if not loaded 
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
##################################################################################################
loadBondingModule() {
    lsmod | grep "bonding" > /dev/null 2>&1
    if [[  $? != 0 ]]; then
        echo -e "Bonding Module not loaded in the Kernel.\nLoading the bonding module in the kernel."
        modprobe --first-time bonding
        if [[ $? == 0 ]]; then
            echo "Bonding Module Successfully loaded to kernel"
        else
            echo "Loading the Bonding Module Failed!!"
            exit 1
        fi
    fi
}

##################################################################################################
# Check if there is any existing bond interface and display the bond interface names if available.
# Globals:
#   CHK_BOND_PATH   filepath for /proc/net/bonding
#   PRESENT_BONDS   Current available bond interface comma separated names
# Arguments:
#   None
# Returns:
#   Sets Values of PRESENT_BONDS global variable with the existing bond interface names
##################################################################################################
checkExistingBond() {
    # Iterates through /proc/net/bonding/* to display the existing bond interfaces.
    for each in $CHK_BOND_PATH/*; do
        if [[ ! -z $(echo $each | grep -v "$CHK_BOND_PATH/\*") ]]; then
            PRESENT_BONDS="$(echo $each | awk -F "/" '{print $NF}'),$PRESENT_BONDS"
        fi
    done 

    if [[ ! -z $PRESENT_BONDS ]];then
        PRESENT_BONDS=$(echo $PRESENT_BONDS | sed -e 's/,$//')
        echo "Existing bond interface/s  $PRESENT_BONDS found."     
    fi
}

##################################################################################################
# Builds the options to be used in the bond configuration file parameter BONDING_OPTS
# The BOND_OPTS needs to be duplicated since the default and arguments passed values will differ and
# the options passed in the arguments will override the default one.
# miimon is used for defining the time interval to check the status of the slave interfaces.
# Globals:
#   BOND_OPTS   Contains the Bonding Options passed in the arguments while executing the script
#   BOND_MODE   Contains the numeric or alphabetical mode of the bonding interface
# Arguments:
#   $1 = bond_mode
#   $2 = bonding_options
# Returns:
#   None
##################################################################################################
buildBondOpts() {
    local bond_mode=$1
    local bonding_options=$2

    if [[ -z $bonding_options ]]; then
        case $bond_mode in
            0|balance-rr) BOND_OPTS="mode=0 miimon=100"
            ;;
            1|active-backup) BOND_OPTS="mode=1 miimon=100 fail_over_mac=1"
            ;;
            2|balance-xor) BOND_OPTS="mode=2 miimon=100"
            ;;
            3|broadcast) BOND_OPTS="mode=3 miimon=100"
            ;;
            4|802\.ad) BOND_OPTS="mode=4 miimon=100"
            ;;
            5|balance-tlb) BOND_OPTS="mode=5 miimon=100"
            ;;
            6|balance-alb) BOND_OPTS="mode=6 miimon=100"
        esac 
    else
        case $bond_mode in
            0|balance-rr) BOND_OPTS="mode=0 $BOND_OPTS"
            ;;
            1|active-backup) BOND_OPTS="mode=1 $BOND_OPTS"
            ;;
            2|balance-xor) BOND_OPTS="mode=2 $BOND_OPTS"
            ;;
            3|broadcast) BOND_OPTS="mode=3 $BOND_OPTS"
            ;;
            4|802\.ad) BOND_OPTS="mode=4 $BOND_OPTS"
            ;;
            5|balance-tlb) BOND_OPTS="mode=5 $BOND_OPTS"
            ;;
            6|balance-alb) BOND_OPTS="mode=6 $BOND_OPTS"
        esac
    fi
}

##################################################################################################
# Checks the if Interfaces provided (in the argument -i or all interfaces in -k argument) 
# is detected/present in the system and checks if they are slave of the existing bond Interface.
# If any interfaces are detected to be a salve of an existing bond they will be displayed.
# Globals:
#   INTERFACES              Contains the comma separated value of the interfaces passed in 
#                           the -i argument
#   CHK_INTERFACE_FILE      Alias for /proc/net/dev
#   CHK_BOND_PATH           Alias for /proc/net/bonding
#   MASTER_BOND             Contains the value of the bond master of a interface
# Arguments:
#   $1 = interfaces csv
# Returns:
#   None
##################################################################################################
checkSlaveInterfaces() {
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "1" "${BASH_LINENO[0]}"
    local interfaces="$1"
    local master_bond=""

    if [[ -z $(echo $interfaces | awk -F "," '{print $2}') ]] ; then
        echo "Minimum of two interfaces are needed to make a LAG interface. Found only one physical interface." 
        exit 1
    fi

    # Finds the name of physical interfaces provided in the options is present in the /proc/net/dev file
    while read -r int; do
        grep $int $CHK_INTERFACE_FILE > /dev/null 2>&1
        if [[ $? != 0  ]]; then
            echo "Interface $int not found in the system. Please recheck the interface name."
            exit 1
        fi

        if [[ ! -z $(ip addr show $int | grep -w "inet") ]]; then
            echo "It seems that the IP address is configured for device $int. Please verify."
            echo "Creating LAG Interface failed!"
            exit 1
        fi
        
        # Finds if the physical interfaces provided in the options is already a slave of 
        # an existing bond interfaces by running recursive grep against /proc/net/bonding/* directory.
        master_bond=$(grep -il $int $CHK_BOND_PATH/* 2> /dev/null)
        if [[ ! -z $master_bond ]]; then
            echo "$int is slave of bond interface $(echo $master_bond | awk -F "/" '{print $NF}'). Creating bond interface failed."
            exit 1
        fi
    done < <(echo $interfaces | sed 's/,/\n/g')
}

##################################################################################################
# Display the list of useful information of Available Interfaces detected by the system for creating bond interdace
# Globals:
#   CHK_BOND_PATH           Alias for /proc/net/bonding
# Arguments:
#   None
# Returns:
#   None
##################################################################################################
listInterfaces(){
    # Displays the available bond an physical interfaces by processing the information 
    # present in /proc/net/dev file, /proc/net/bonding/* directory and ip addr command
    local bond_ints=""
    local slave_ints=""
    local ip_configured_ints=""
    local available_ints=""

    while read int; do
        if [[ -f "$CHK_BOND_PATH/$int" ]]; then 
            bond_ints="$int,$bond_ints"
        elif [[ ! -z $(grep -il $int $CHK_BOND_PATH/* 2> /dev/null) ]]; then
            slave_ints="$(grep -il $int $CHK_BOND_PATH/* | awk -F "/" '{print $NF}'):$int,$slave_ints"
        elif [[ ! -z $(ip addr show $int | grep -E "inet" | grep -v "inet6") ]]; then
            ip_configured_ints="$int,$ip_configured_ints"
        else
            available_ints="$int,$available_ints"
        fi
    done < <(awk -F: '/:/{print $1}' /proc/net/dev | sort)

    echo -e "Bond Interfaces: \n\t$(echo $bond_ints | sed 's/,/\n\t/g')"
    echo -e "Current Configured Slave Interfaces: \n\t$(echo $slave_ints | sed 's/,/\n\t/g')"
    echo -e "Current IP Configured Interfaces:\n\t$(echo $ip_configured_ints | sed 's/,/\n\t/g')"
    echo -e "Interfaces Available for LAG:\n\t$(echo $available_ints | sed 's/,/\n\t/g')"
}



##################################################################################################
# Creates a configuration file for the slave interfaces used as a slave interface for a bond interface.
# Globals:
#   INTERFACE_CONFIG_PATH               Alias for /etc/sysconfig/network-scripts
#   INTERFACE_CONFIG_FILE               Holds the filepath of the interface configuration file
#   INTERFACES                          Holds the comma separated values for slave interfaces
# Arguments:
#   $1              First positional argument for passing the bond master name
# Usage:
#   changePhysIntConf <name_of_bond_master>
# Returns:
#   None
##################################################################################################
changePhysIntConf(){
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "2" "${BASH_LINENO[0]}"
    local interfaces="$1"
    local bond_master="$2"

    while read -r int; do
        writeIntConfigFile "SLAVE" "$int" "$bond_master"
        ifdown $int || (>&2 echo "Warning: Failed to bring $int down")
        ifup $int || (>&2 echo "Warning: Failed to bring $int up")
    done < <(echo $interfaces | sed 's/,/\n/g')
}


##################################################################################################
# Creates a configuration file for the newly created bond interface
# Globals:
#   BOND_NUM                    The number of the bond interface
#   BOND_NUM_LATEST             The number from which the new bond interface will be created
#   BOND_CONFIG_FILE            The alias for the filepath of the configuration of new bond interface
#   BOND_INT                    Holds the value of the new bond interface to be created
#   BOND_OPTS                   Holds the value of the bonding options built from buildBondOpts function
# Arguments:
#   $1 = present_bonds
#   $2 = bonding_options
# Returns:
#   None
##################################################################################################
createBondInterface() {
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "2" "${BASH_LINENO[0]}"
    local present_bonds=$1
    local bonding_options=$2

    while read -r int; do
        if [[ ! -z $(echo $int | grep 'bond') ]]; then
            local bond_num="$(echo $int | awk -F 'bond' '{print $2}'), $bond_num"
        fi
    done < <(echo $present_bonds | sed -e 's/,/\n/g')
    
    local bond_num_latest=$(echo $bond_num | sed -e 's/,$//' | sed 's/,/\n/g' | sort -n | tail -n1)

    local bond_interface_name="bond$(($bond_num_latest+1))"
    echo "Creating the new bond configuration file for $bond_interface_name"
    writeIntConfigFile "MASTER" "$bond_interface_name" "$bonding_options"
    ifup $bond_interface_name && \
    echo "Bond interface $BOND_INT created successfully" || \
    (>&2 echo "Warning: Failed to bring $bond_interface_name up")

    BOND_INT="$bond_interface_name"
}

writeIntConfigFile() {
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "3" "${BASH_LINENO[0]}"
    local interface_mode=$1
    local interface_name=$2
    local interface_config_filepath="$INTERFACE_CONFIG_PATH/ifcfg-$interface_name"
    local bonding_opts=""
    local master_name=""
    local master_mod="$4"

    #use case statement
    case ${interface_mode} in
        "SLAVE")
            master_name=$3
            cat << INT_CONF_TEMP > "$interface_config_filepath"
DEVICE=$interface_name
BOOTPROTO=none
MASTER=$master_name
SLAVE=yes
ONBOOT=on
INT_CONF_TEMP

            if [[ $? != 0 ]]; then
                (>&2 echo "Error: Couldn't write the configuration file of $interface_name interface")
                local bond_config_filepath="$INTERFACE_CONFIG_PATH/ifcfg-$master_name"
                rm -f "$bond_config_filepath"
                exit 1
            fi
        ;;

        "SLAVEREMOVE")
            cat << INT_CONF_TEMP > "$interface_config_filepath"
DEVICE=$interface_name
BOOTPROTO=none
SLAVE=yes
ONBOOT=off
INT_CONF_TEMP

            if [[ $? != 0 ]]; then
                (>&2 echo "Error: Couldn't write the configuration file of $interface_name interface")
                exit 1
            fi
        ;;

        "MASTER")
            if [[ $master_mod == 'MODIFY' ]]; then
                if [[ ! -f $interface_config_filepath ]]; then
                    (>&2 echo "Error: $interface_config_filepath configuration file does not exists.")
                    exit 1
                fi
            elif [[ -f $interface_config_filepath ]]; then
                (>&2 echo "Error: $interface_config_filepath configuration file already exists.")
                exit 1
            fi

            bonding_opts=$3
            cat << CONF_TEMP > "$interface_config_filepath"
DEVICE=$interface_name
TYPE=Bond
BONDING_MASTER=yes
BOOTPROTO=dhcp
ONBOOT=yes
BONDING_OPTS="$bonding_opts"
CONF_TEMP

            if [[ $? != 0 ]]; then
                (>&2 echo "Error: Couldn't write the configuration file of $interface_name interface")
                exit 1
            fi    
        ;;
    esac
    
}

createIntConfigBackup(){
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "1" "${BASH_LINENO[0]}"
    local interface_name="$1"
    local backup_path="$CONF_BACKUP_PATH"
    local interface_config_filepath="$INTERFACE_CONFIG_PATH/ifcfg-$interface_name"

    if [[ ! -d $backup_path ]];then
        mkdir -p $backup_path
    fi

    if [[ -f "$interface_config_filepath" ]]; then
        echo "Creating backup of $interface_config_filepath config file."
        cp -a "$interface_config_filepath" "$backup_path/$interface_name.$(date +%Y-%m-%d_%H%M%S)"

        if [[ $? == 0 ]];then
           echo "Backup of $interface_config_filepath successfully created at $backup_path" 
        else
            (>&2 echo "Warning: Couldn't create a backup of $interface_config_filepath at $backup_path")
        fi
    fi
}

checkFunctionArgs() {
    local name_of_function=$1
    local num_of_args=$2
    local expected_num_of_args=$3
    local func_line_number=$4

    if [[ $# -lt 4 ]]; then
        (>&2 echo "Error: $0 function expects minimum of 4 arguments.")
        exit 1
    else
        if [[ $num_of_args -lt $expected_num_of_args ]]; then
            (>&2 echo "Error: $name_of_function function expects minimum of $expected_num_of_args arguments. Occured in $func_line_number line number.")
            exit 1
        fi
    fi
}


##################################################################################################
# Modifies the configuration of the existing bond interface
# Globals:
#   CHK_BOND_PATH               Alias for /proc/net/bonding
#   BOND_NAME                   The interface name for the bond to be modified
#   INTERFACE_CONFIG_PATH       Alias for /etc/sysconfig/network-scripts/
#   BOND_CONFIG_FILE            Alias for the filepath of the bond configuration to be modified
#   BOND_OPTS                   Bonding options built from buildBondOpts function
# Arguments:
#   None
# Returns:
#   None
##################################################################################################
modifyBondInterface() {
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "2" "${BASH_LINENO[0]}"
    local bond_interface_name="$1"
    local bonding_options="$2"

    if [[ -f "$CHK_BOND_PATH/$bond_interface_name" ]]; then
        echo "Reconfiguring LAG Interface $bond_interface_name"
        createIntConfigBackup "$bond_interface_name"
        writeIntConfigFile "MASTER" "$bond_interface_name" "$bonding_options" "MODIFY"
        ifdown $bond_interface_name || (>&2 echo "Warning: Failed to bring $bond_interface_name down")
        ifup $bond_interface_name || (>&2 echo "Warning: Failed to bring $bond_interface_name up")
    else
        echo "Error: No existing configuration of LAG Interface $bond_interface_name found. Reconfiguring exited!"
        exit 1
    fi
}

##################################################################################################
# Removes the exising bond configuration and changes the existing slave interfaces' configuration
# Before removing bond configuration and the changing the slave interface they are backed up.
# Globals:
#   CHK_BOND_PATH           Alias for /proc/net/bonding/
#   BOND_NAME               Bond interface name to be removed
#   INTERFACE_CONFIG_FILE   Alias for the filepath of configuration of the slave interface
#   INTERFACE_CONFIG_PATH   Alias for /etc/sysconfig/network-scripts/
# Arguments:
#   None 
# Returns:
#   None
##################################################################################################
removeBondInterface(){
    checkFunctionArgs "${FUNCNAME[0]}()" "$#" "1" "${BASH_LINENO[0]}"
    local bond_name="$1"
    local interface_config_file=""
    local bond_config_file="$INTERFACE_CONFIG_PATH/ifcfg-$bond_name"

    if [[ -f "$CHK_BOND_PATH/$bond_name" ]]; then
        echo "Removing Slave Interfaces for LAG Interface $bond_name"

        while read slaveInt; do
            interface_config_file="$INTERFACE_CONFIG_PATH/ifcfg-$slaveInt"
            echo "Removing slave interface $slaveInt from $bond_name"
            createIntConfigBackup "$slaveInt" 
            writeIntConfigFile "SLAVEREMOVE" "$slaveInt" "$bond_name"

            ifdown $slaveInt || (>&2 echo "Warning: Failed to bring down $slaveInt down")
            ifup $slaveInt || (>&2 echo "Warning: Failed to bring $slaveInt up")
        done < <(grep -i "slave interface: " "$CHK_BOND_PATH/$bond_name" | awk -F ": " '{print $2}')

        echo "Removing LAG Interface $BOND_NAME"
        ifdown $BOND_NAME || (>&2 echo "Failed to bring $BOND_NAME down")
        createIntConfigBackup "$bond_name"
        rm -f "$bond_config_file"
        if [[ $? != 0 ]]; then
            echo "Couldn't remove the LAG Interface $bond_config_file"
            exit 1
        fi
        echo "LAG Interface $bond_name removed successfully."
    else
        echo "No LAG Interface $bond_name found!"
    fi
}

main() {
    if [[ $(id -u) != 0 ]]; then
        echo "Error: Please execute the Script with root permissions."
        exit 1
    fi

    while getopts "b:i:o:m:r:clk" options; do
        case $options in
            b) BOND_MODE=$OPTARG
            ;;
            i) INTERFACES=$OPTARG
            ;;
            o) BOND_OPTS=$OPTARG
            ;;
            m) MODIFY_BOND=1 && BOND_NAME=$OPTARG && ACTION_FLAG=$(($ACTION_FLAG+1))
            ;;
            r) REMOVE_BOND=1 && BOND_NAME=$OPTARG && ACTION_FLAG=$(($ACTION_FLAG+1))
            ;;
            l) LIST_BOND=1 && ACTION_FLAG=$(($ACTION_FLAG+1))
            ;;
            c) CREATE_BOND=1 && ACTION_FLAG=$(($ACTION_FLAG+1))
            ;;
            k) ADD_ALL_INTERFACES=1 && ACTION_FLAG=$(($ACTION_FLAG+1))
            ;;
            *) displayUsage
            ;;
        esac
    done
    
    if [[ $ACTION_FLAG -gt 1 ]] ; then
       echo "Error: Too many arguments used. Only one is supported at a time."
       displayUsage
    fi
    
    
    ##### DECLARING THE PATH VARIABLES USED GLOBALLY
    
    CHK_BOND_PATH="/proc/net/bonding"
    CHK_INTERFACE_FILE="/proc/net/dev"
    INTERFACE_CONFIG_PATH="/etc/sysconfig/network-scripts"
    CONF_BACKUP_PATH="/var/int-config-backup/"
    PRESENT_BONDS=""                # Holds the comma separated value for the existing bond interfaces
    
    loadBondingModule
    if [[ $LIST_BOND == 1 ]]; then
        listInterfaces
    elif [[ $MODIFY_BOND == 1 && ! -z $BOND_NAME && ! -z $BOND_MODE && ! -z $BOND_OPTS ]]; then
        buildBondOpts "$BOND_MODE" "$BOND_OPTS"
        modifyBondInterface "$BOND_NAME" "$BOND_OPTS"
    elif [[ $REMOVE_BOND == 1 && ! -z $BOND_NAME ]]; then
        removeBondInterface "$BOND_NAME"
    elif [[ $CREATE_BOND == 1 && ! -z $BOND_MODE && ! -z $INTERFACES ]]; then
        checkExistingBond
        checkSlaveInterfaces "$INTERFACES"
        buildBondOpts "$BOND_MODE" "$BOND_OPTS"
        createBondInterface "$PRESENT_BONDS" "$BOND_OPTS"
        changePhysIntConf "$INTERFACES" "$BOND_INT"
    elif [[ $ADD_ALL_INTERFACES == 1 && ! -z $BOND_MODE ]]; then
        checkExistingBond
        if [[ -z "$PRESENT_BONDS" ]];then
            INTERFACES=$(grep -vE  "lo" $CHK_INTERFACE_FILE | awk -F: '/:/{print $1}' | sed "s/\n/,/g") 
        else
            INTERFACES=$(grep -vE  "$(echo "$PRESENT_BONDS" | sed 's/,/|/g')|lo" $CHK_INTERFACE_FILE | awk -F: '/:/{print $1}' | sed "s/\n/,/g") 
        fi

        echo $INTERFACES
        checkSlaveInterfaces "$INTERFACES"
        buildBondOpts "$BOND_MODE" "$BOND_OPTS"
        createBondInterface "$PRESENT_BONDS" "$BOND_OPTS"
        changePhysIntConf "$INTERFACES" "$BOND_INT"
    else
        displayUsage
    fi
}

main "$@"
