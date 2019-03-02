GPGServices
===========

GPGServices allows you to encrypt, decrypt, sign and verify  
files and texts from the services menu of Mac OS X.

Updates
-------

The latest releases of GPGServices can be found on our [official website](https://gpgtools.org/gpgservices/).

For the latest news and updates check our [Twitter](https://twitter.com/gpgtools).

Visit our [support page](https://gpgtools.tenderapp.com/) if you have questions or need help setting up your system and using GPGServices.


Build
-----

### Clone the repository
```bash
git clone https://github.com/GPGTools/GPGServices.git
cd GPGServices
```

### Build
```bash
make
```


Don't forget to install [MacGPG2](https://github.com/GPGTools/MacGPG2)
and [Libmacgpg](https://github.com/GPGTools/Libmacgpg).  
You may need logout and login to enable GPGServices.  
Have a look at System Preferences > Keyboard > Keyboard Shortcuts > Services > Text.  
Enjoy your custom GPGServices.


Uninstalling
------------

Navigate to `/Library/Services/` and remove `GPGServices.service.app`.


System Requirements
-------------------

* Mac OS X >= 10.6
* Libmacgpg
* GnuPG
