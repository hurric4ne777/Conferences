#!/bin/bash

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# What is scoped to my Computer Groups?
#
# In this script we will utilize the Jamf Pro API to determine what Policies are assigned
# to your Computer Groups.
#
#
# OBJECTIVES
#       - Create a list of all Smart Groups
#       - Provide a list of what is scoped to each Smart Group
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# USER VARIABLES
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

jamfURL="https://acme.jamfcloud.com"
jamfUser="apiread"
jamfPass="password"
currentUser=$(/usr/bin/stat -f%Su /dev/console)

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# APPLICATION
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

## Retrieve & Extract Computer Group IDs/Names & Build Array
compGroupData=$( curl -k -s -u "$jamfUser":"$jamfPass" $jamfURL/JSSResource/computergroups -H "Accept: application/xml" -X GET )
compGrpSize=$( echo $compGroupData | xpath "//computer_groups/size/text()" )
index=0
declare -a compGrpNames
declare -a compGrpIDs
while [ $index -lt ${compGrpSize} ]; do
    element=$(($index+1))
    compGrpName=$( echo $compGroupData | xpath "//computer_groups/computer_group[${element}]/name/text()" )
    compGrpID=$( echo $compGroupData | xpath "//computer_groups/computer_group[${element}]/id/text()" )
    echo "Computer Group ID: $compGrpID"
    echo "Computer Group Name: $compGrpName"
    compGrpNames[$index]="$compGrpName"
    compGrpIDs[$index]="$compGrpID"
    declare -a compGrp${compGrpID}
    ((index++))
done

## Retrieve & Filter Policy Data
echo "Retrieving List of All Policy IDs..."
unset policyIDs
policyIDs=( $( curl -k -s -u "$jamfUser":"$jamfPass" $jamfURL/JSSResource/policies -H "Accept: application/xml" -X GET | /usr/bin/perl -lne 'BEGIN{undef $/} while (/<id>(.*?)<\/id>/sg){print $1}' ) )
for i in "${policyIDs[@]}"; do
    echo "Retrieving Policy ID ${i}'s' Data..."
    policyData=$( curl -k -s -u "$jamfUser":"$jamfPass" $jamfURL/JSSResource/policies/id/${i} -H "Accept: application/xml" -X GET )
    policyName=$( echo $policyData | xpath "//policy/general/name/text()" )
    ## Check if is a Jamf Remote Policy
    echo "Checking if this is a Jamf Remote Policy..."
    if [[ $policyName == $( echo $policyName | egrep -B1 '[0-9]+-[0-9]{2}-[0-9]{2} at [0-9]{1,2}:[0-9]{2,2} [AP]M \| .* \| .*' ) ]]; then
        ## This is a Jamf Remote Policy
        ## Setting policy name in array to "JamfRemotePolicy-Ignore"
        echo "    This is a Jamf Remote policy"
        continue
    else
        ## This is NOT a Casper Remote Policy
        ## Storing Policy Name and Grabbing Scope Data
        echo "    This is a standard policy"
        ## Extract Scoped Computer Group ID(s)
        unset grpID
        grpID=( $( echo $policyData | /usr/bin/perl -lne 'BEGIN{undef $/} while (/<computer_groups>(.*?)<\/computer_groups>/sg){print $1}' | /usr/bin/perl -lne 'BEGIN{undef $/} while (/<id>(.*?)<\/id>/sg){print $1}' ) )
        if [[ ${#grpID[@]} -eq 0 ]]; then
            echo "No Computer Groups Scoped in Policy ${policyIDs[$i]}..."
        else
            echo "Computer Groups found for Policy ${policyIDs[$i]}..."
            for n in "${grpID[@]}"; do
                eval compGrp$n+=\(\"$policyName \(Policy\)\"\)
            done
        fi
    fi
    sleep .3
done

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# BUILD HTML REPORT
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

reportDate=$(/bin/date "+%Y-%m-%d %H%M%S")
reportName="/Users/${currentUser}/Desktop/Jamf Pro Computer Group Report - $reportDate.html"
echo "<html>
<head>
<title>Jamf Pro Computer Groups Report - $reportDate</title>
</head>
<body>
<h1>Jamf Pro Computer Groups Report</h1>
<i>Report Date: $reportDate<br/>Jamf Pro server: $jamfURL</i>
<hr/>
<p/>" > "$reportName"
for (( x = 0 ; x < ${#compGrpNames[@]} ; x++ )); do
    echo "<b>${compGrpNames[$x]}</b><br/><ul>" >> "$reportName"
    groupID="${compGrpIDs[$x]}"
    yCount=$(eval echo \${#compGrp$groupID[@]})
    for (( y = 0 ; y < $yCount ; y++ )); do
        echo "<li>$(eval echo \${compGrp$groupID[$y]})</li>" >> "$reportName"
    done
    echo "</ul><p/>" >> "$reportName"
done
echo "</body>
</html>" >> "$reportName"

open "$reportName"

exit 0
