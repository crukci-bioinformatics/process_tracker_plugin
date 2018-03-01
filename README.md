## The Project State Plugin

This [Redmine](http://www.redmine.org/) plugin adds the notion of the
*state* of an issue, as a coarser-grained grouping than the built-in
*status*.  In addition, it generates a report showing issues that meet
certain criteria indicating that they need attention.  This plugin is
tailored for the workflows used in the  Bioinformatics Core of the
Cancer Research UK Cambridge Institute, but may be of some value to others.
For a discussion of the workflow, see our
[process documentation](https://github.com/crukci-bioinformatics/process_docs/blob/master/proposal/process_proposal.md),
though this present document is the definitive description (aside from the
code) of what the plugin does.

States include:

* *Prepare* -- The issue has been discussed with the Core, an experimental
             design meeting has occurred, and the researcher is preparing
             samples.
* *Submit* -- The samples have been submitted for sequencing.
* *Ready* -- Samples have been sequenced, and are ready for computational
           analysis.
* *Active* -- A computational analyst is actively working on the issue.
* *Hold* -- The data are available, but no analyis is currently free to work
          on the analysis.
* *Post* -- The results have been delivered to the researcher.

Broadly speaking, transitions should be forward:
*Prepare* --> *Submit* --> *Ready* --> *Active* --> *Post*, possibly with a
detour through *Hold*.  Each issue also has a current *timeout*, as well as
a *hour limit*.  Issues will be flagged if;

* more hours have been logged with the issue than the *hour limit*;
* the issue has been in the current state longer than *timeout* days, or
* in the case of projects in state *Active*, the issue has gone more than
  *timeout* days without activity being logged;
* the issue is not in state *Prepare*, but no analyst has been assigned;
* the issue's *status* and *state* do not match.

Two state transitions are automated:

* when samples are submitted for sequencing, the issue will move from
  *Prepare* to *Submit*, based on receiving a REST API call from our Genomics
  LIMS;
* when sequences are available from Genomics, the issue will move to *Ready*,
  based on a REST API call from the LIMS,
  unless it is already at a state later than that in the cycle.

Some state transitions should trigger notifications to the researcher:

* when the task moves to *Active*, the researcher is notified, along with an
  estimate of the time until results may be available;
* when the task is set to state *Post*, the researcher is notified that no
  further activity should be expected, unless requested by the researcher.

The plugin includes defaults for *timeout* and *hour limit*, based on the
current state and tracker, respectively.  The limits may be changed by
the Core.

## Implementation

The plugin follows Rails and Redmine conventions, as of Rails 4.2 and
Redmine 3.1.0.

### Initialization

When the plugin is installed, the plugin migration Rake task will create
tables to store the default state timeouts, default logged-hour limits,
and the mapping between statuses and states.  (This is a many-to-one mapping:
each status must be associated with exactly one state, but several statuses may
map to the same state.)

When the Redmine server is started, several initialization steps take place:

* ensure that the plugin's custom fields are present (creating them
  if necessary);
* ensure that the custom fields are associated with the relevant trackers,
  based on the values of configuration variables described below;
* ensure that the projects that should be included in the report have the
  custom fields associated with them (and other projects do not);
* ensure that all issues under the relevant projects have values for the
  custom fields, setting them to defaults if they are not present.

These steps must take place on every restart, since changing the value of
the **Root Projects** configuration variable will change which projects
should have these fields associated with them.

In addition, one initialization step needs to be done the first time the
plugin is installed (after the plugin migration step).  The Rake task
"db:seed" must be run, to populate the transaction journal with state
changes corresponding to historical status changes.

### Configuration

The plugin can be configured if the current user is marked as an "admin"
user (typically just the user named "admin").  Follow "Administration" --> 
"Plugins" --> "Configure" on the "Project State" plugin to edit these
configuration values:

* **Root Projects** --- Redmine issues that are in these projects, or
sub-projects of these, are included in the report.  If this value is changed,
the Redmine server (in this case *httpd*) **must** be restarted.
* **Alert Logins** --- Email will be sent to these accounts when an issue's
"logged hours" limit is raised, or the "days in state" limit is raised.  Email
will *not* be sent if the user making the change is included in this list.
* **Trackers to Filter** --- Trackers in this list will be excluded from the
"filtered" report.
* **Filter Projects** --- Projects in this list (normally a subset of the
**Root Projects** list) will be excluded from the "filtered" report.
* **Trackers to Keep** --- Issues in a project in the **Filter Projects** list
will be **included** in the report, if the tracker is in this list.
* **Trackers to Ignore** --- Issues with these trackers will never be included
in the report.

All variables may include multiple values, separated by semicolons.

Configuration of the default hour limits, state timeouts, and mapping of
statuses to states may be done via the "**Configure Project State Defaults**"
link on the plugin configuration page.  If the defaults need to be changed,
or a new tracker or status has been
added, this page allows updating of those values.  If the user is not an
admin user, the page shows the current values, read-only.
