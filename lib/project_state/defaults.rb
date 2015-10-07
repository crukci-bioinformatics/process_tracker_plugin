module ProjectStatePlugin

  module Defaults

    UNASSIGNED = -1

    STATE_TIMEOUT_DEFAULTS = {'Prepare' => 180,
                              'Submit' => 120,
                              'Ready' => 7,
                              'Active' => 21,
                              'Hold' => 14,
                              'Post' => 90,
                              'Ongoing' => 180}

    INTERESTING = ['Prepare','Submit','Ready','Active','Hold','Post']

    ORDERING = {'Ongoing' => 0,
                'Prepare' => 1,
                'Submit' => 2,
                'Ready' => 3,
                'Active' => 4,
                'Hold' => 5,
                'Post' => 6}

    HOUR_LIMIT_DEFAULTS = {
      'Class 0 - Short Task'          => 20,
      'Class I - Microarray-Genomics' => 40,
      'Class I - Proteomics'          => 40,
      'Class I - Sequencing-Genomics' => 40,
      'Class I - Statistics'          => 40,
      'Class I - Analysis'            => 40,
      'Class II - Researcher Based'   => 50,
      'Class III - Research Project'  => 60,
      'Other'                         => 20,
      'Support'                       => 20,
      'Bug'                           => 20,
      'Feature'                       => 20
    }

    PROJECT_STATE_DEFAULTS = { 2 => 'Ready',
                               5 => 'Post',
                               7 => 'Ongoing',
                              11 => 'Post',
                              12 => 'Active',
                              14 => 'Prepare',
                              15 => 'Prepare',
                              17 => 'Submit',
                              18 => 'Submit',
                              19 => 'Submit',
                              20 => 'Submit',
                              21 => 'Submit',
                              22 => 'Prepare',
                              23 => 'Submit',
                              24 => 'Post',
                              27 => 'Prepare',
                              28 => 'Prepare',
                              29 => 'Hold',
                              30 => 'Active'
    }

  end
end
