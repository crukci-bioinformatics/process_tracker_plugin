## The Project State Plugin

This [Redmine](http://www.redmine.org/) plugin adds the notion of the
*state* of an issue, as a coarser-grained grouping than the built-in
*status*.  In addition, it generates a report showing issues that meet
certain criteria indicating that they need attention.  This plugin is
tailored for the workflows used in the  Bioinformatics Core of the
Cancer Research UK Cambridge Institute, but may be of some value to others.
For a discussion of the workflow, see our
[process documentation](https://github.com/crukci-bioinformatics/process_docs/blob/master/proposal/process_proposal.md),
though this document is the definitive description (aside from the code) of
what the plugin does.

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
* the issue is not in state *Prepare*, but no analyst has been assigned.

Two state transitions are automated:

* when samples are submitted for sequencing, the issue will move from
  *Prepare* to *Submit*, based on receiving a REST API call from our Genomics
  LIMS;
* when sequences are available from Genomics, the issue will move to *Ready*,
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

The plugin follows Redmine conventions, as of Redmine 3.1.0.

### Initialization

Certain initialization steps should only need to be done the first time the
plugin is used.  These are handled by the "rake db:seed" task.
Others have to be checked on each Redmine restart, because plugin configuration
values may have changed.  Details are below.

Stages of initialization:

* Create tables for default values (state timeouts, hour limits) -- done by
  migration code.
* Populate defaults tables with actual defaults (via db/seeds.rb).
* * populate tables
* * create new custom fields
* * ensure that journal includes entries for historical status changes
* * run "rake db:seed" to populate
* On each restart:
* * get list of "root" projects from "root_projects" configuration data
* * ensure custom fields are associated with each relevant project
* * ensure all issues in relevant projects have values for custom variables
  (use defaults if missing).
* * these steps must be done every restart, since configuration values may have
    been changed, and there is no appropriate hook to trigger these steps as
    the configuration value is changed.
