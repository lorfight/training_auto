*** Settings ***
Resource    ../resource/openbrowser.resource

*** Variables ***
${url}    https://rophim9.vip/
${banner_link}    //div[@class="jsx-1c22a3ff2b7d20d4 catfish-bottom-double"]//a[contains(@href,"fo88")]

*** Test Cases ***
Action rophim
    Access url    ${url}
    Click banner
    Switch new window
    ${new_link}    Get new link
    Log To Console    Link banner: ${new_link}
    ${actual_link}    Set Variable    https://fo88.host/?a=197360cfa68cec96976dc7c91782975f&utm_campaign=martech&utm_source=rophim9.com&utm_content=movie&utm_medium=catfish-left-728x90&referrer_domain=rophim9.vip
    Should Be Equal    ${actual_link}    ${new_link}
    Sleep    5s

*** Keywords ***
Click banner
    Wait Until Element Is Visible    ${banner_link}    10s
    Scroll Element Into View    ${banner_link}
    Click Element    ${banner_link}

Switch new window
    Switch window    NEW

Get new link
    ${new_link}    Get Location
    RETURN    ${new_link}