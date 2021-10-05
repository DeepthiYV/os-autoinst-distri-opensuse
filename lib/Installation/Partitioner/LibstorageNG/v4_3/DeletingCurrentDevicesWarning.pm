# SUSE's openQA tests
#
# Copyright © 2020 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved. This file is offered as-is,
# without any warranty.

# Summary: The class introduces methods in Expert Partitioner to handle
# a confirmation warning when deleting current devices is required.
# Maintainer: QE YaST <qa-sle-yast@suse.de>

package Installation::Partitioner::LibstorageNG::v4_3::DeletingCurrentDevicesWarning;
use strict;
use warnings;
use parent 'Installation::Popups::YesNoPopup';

sub init {
    my ($self) = @_;
    $self->SUPER::init();
    $self->{lbl_warning} = $self->{app}->label({label => 'Confirm Deleting of Current Devices'});
    return $self;
}

1;
