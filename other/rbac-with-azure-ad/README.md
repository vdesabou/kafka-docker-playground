# Testing Azure AD with RBAC

LDAP authentication with Azure Active Directory can be setup, see the documentation [here](https://docs.microsoft.com/en-us/azure/active-directory/fundamentals/auth-ldap)

Here are some notes on the setup:

## Create and configure an Azure AD DS instance

See doc [here](https://docs.microsoft.com/en-us/azure/active-directory-domain-services/tutorial-create-instance)

Steps that I've done:

* Create an Azure account (Pay As You Go)
* Follow https://docs.microsoft.com/en-us/azure/active-directory-domain-services/tutorial-create-instance
* Follow https://docs.microsoft.com/en-us/azure/active-directory-domain-services/tutorial-configure-networking#create-a-virtual-network-subnet
* Add security rule for LDAPS port 636 https://docs.microsoft.com/en-us/azure/active-directory-domain-services/tutorial-configure-ldaps#lock-down-secure-ldap-access-over-the-internet
