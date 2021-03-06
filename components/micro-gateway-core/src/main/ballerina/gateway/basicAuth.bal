// Copyright (c)  WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file   except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/log;
import ballerina/auth;
import ballerina/config;
import ballerina/runtime;
import ballerina/system;
import ballerina/time;
import ballerina/io;
import ballerina/reflect;
import ballerina/crypto;
import ballerina/encoding;

public type BasicAuthUtils object {


    http:AuthnHandlerChain authnHandlerChain;

    public function __init(http:AuthnHandlerChain authnHandlerChain) {
        self.authnHandlerChain = authnHandlerChain;
    }

    public function processRequest(http:Caller caller, http:Request request, http:FilterContext context)
                        returns boolean {

        boolean isAuthenticated;
        //API authentication info
        AuthenticationContext authenticationContext = {};
        boolean isAuthorized;
        string[] providerIds = [AUTHN_SCHEME_BASIC];
        //set Username from the request
        string authHead = request.getHeader(AUTHORIZATION_HEADER);
        string[] headers = authHead.trim().split("\\s* \\s*");
        string encodedCredentials = headers[1];
        byte[]|error decodedCredentials =  encoding:decodeBase64(encodedCredentials);
        //Extract username and password from the request
        string userName;
        string passWord;
        if(decodedCredentials is byte[]){
        string  decodedCredentialsString =  encoding:byteArrayToString(decodedCredentials);


            if (!decodedCredentialsString.contains(":")) {
                setErrorMessageToFilterContext(context, API_AUTH_BASICAUTH_INVALID_FORMAT);
                sendErrorResponse(caller, request, untaint context);
                return false;
            }
            string[] decodedCred = decodedCredentialsString.trim().split(":");
            userName = decodedCred[0];
            printDebug(KEY_AUTHN_FILTER, "Decoded user name from the header : " + userName);
            if (decodedCred.length() < 2) {
                setErrorMessageToFilterContext(context, API_AUTH_INVALID_BASICAUTH_CREDENTIALS);
                sendErrorResponse(caller, request, context);
                return false;
            }
            passWord = decodedCred[1];
        } else {
            printError(KEY_AUTHN_FILTER, "Error while decoding the authorization header for basic authentication");
            setErrorMessageToFilterContext(context, API_AUTH_GENERAL_ERROR);
            sendErrorResponse(caller, request, context);
            return false;
        }

        //Hashing mechanism
        string hashedPass = encoding:encodeHex(crypto:hashSha1(passWord.toByteArray(UTF_8)));
        printDebug(KEY_AUTHN_FILTER, "Hashed password value : " + hashedPass);
        string credentials = userName + ":" + hashedPass;
        string hashedRequest;
        string encodedVal = encoding:encodeBase64(credentials.toByteArray(UTF_8));
        printDebug(KEY_AUTHN_FILTER, "Encoded Auth header value : " + encodedVal);
        hashedRequest = BASIC_PREFIX_WITH_SPACE + encodedVal;
        request.setHeader(AUTHORIZATION_HEADER, hashedRequest);

        printDebug(KEY_AUTHN_FILTER, "Processing request with the Authentication handler chain");
        isAuthorized = self.authnHandlerChain.handleWithSpecificAuthnHandlers(providerIds, request);
        printDebug(KEY_AUTHN_FILTER, "Authentication handler chain returned with value : " + isAuthorized);
        if (!isAuthorized) {
            setErrorMessageToFilterContext(context, API_AUTH_INVALID_BASICAUTH_CREDENTIALS);
            sendErrorResponse(caller, request, untaint context);
            return false;
        }

        int startingTime = getCurrentTime();
        context.attributes[REQUEST_TIME] = startingTime;
        context.attributes[FILTER_FAILED] = false;
        //Set authenticationContext data
        authenticationContext.authenticated = true;
        //Authentication context data is set to default value bacuase in basic authentication we cannot have informtaion on subscription and applications
        authenticationContext.tier = UNAUTHENTICATED_TIER;
        authenticationContext.applicationTier = UNLIMITED_TIER;
        authenticationContext.apiKey = ANONYMOUS_APP_ID;
        //Username is extracted from the request
        authenticationContext.username = userName;
        authenticationContext.applicationId = ANONYMOUS_APP_ID;
        authenticationContext.applicationName = ANONYMOUS_APP_NAME;
        authenticationContext.subscriber = ANONYMOUS_APP_OWNER;
        authenticationContext.consumerKey = ANONYMOUS_CONSUMER_KEY;
        authenticationContext.apiTier = UNAUTHENTICATED_TIER;
        authenticationContext.apiPublisher = USER_NAME_UNKNOWN;
        authenticationContext.subscriberTenantDomain = ANONYMOUS_USER_TENANT_DOMAIN;
        authenticationContext.keyType = ANONYMOUS_CONSUMER_KEY;
        runtime:getInvocationContext().attributes[KEY_TYPE_ATTR] = authenticationContext.keyType;
        context.attributes[AUTHENTICATION_CONTEXT] = authenticationContext;
        isAuthenticated = true;
        return isAuthenticated;
    }
};
