Name:           centos-2-rpm
Version:        0.1
Release:        1%{?dist}
Summary:        An Application for building the AWS Markertplace mappings for CentOS Stream

License:        ASL2.0
URL:            https://github.com/Internethamster/%{name}
Source0:        https://api.github.com/repos/Internethamster/centos-2-awsmp/tarball/development

BuildRequires: python3-devel
Requires: python3-boto3
Requires: python3-pandas

%description An Application for building the AWS Marketplace mappings
for the CentOS Stream images. This is a basic set of instructions for
populating the marketplace excel spreadsheets and verifying that the
images are available in all regions.

%prep
%autosetup


%build
%configure
%make_build


%install
%make_install


%files
%license add-license-file-here
%doc add-docs-here



%changelog
* Mon Dec 26 2022 David Duncan <davdunc@davidduncan.org>
-
