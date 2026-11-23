
*** Settings ***
Library    SeleniumLibrary

*** Keywords ***
Config browser
    ${chrome_options}=    Evaluate
    ...    sys.modules['selenium.webdriver'].ChromeOptions()
    ...    sys

    Call Method    ${chrome_options}    add_argument    --no-sandbox
    Call Method    ${chrome_options}    add_argument    --disable-dev-shm-usage
    Call Method    ${chrome_options}    add_argument    --disable-gpu
    Call Method    ${chrome_options}    add_argument    --window-size\=1920,1080

    RETURN    ${chrome_options}


Access url
    [Arguments]    ${url}

    ${chrome_options}=    Config browser

    Create Webdriver    Chrome    options=${chrome_options}

    Go To    ${url}
