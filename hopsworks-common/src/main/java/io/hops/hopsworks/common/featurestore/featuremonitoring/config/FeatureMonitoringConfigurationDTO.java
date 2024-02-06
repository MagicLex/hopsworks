/*
 * This file is part of Hopsworks
 * Copyright (C) 2024, Hopsworks AB. All rights reserved
 *
 * Hopsworks is free software: you can redistribute it and/or modify it under the terms of
 * the GNU Affero General Public License as published by the Free Software Foundation,
 * either version 3 of the License, or (at your option) any later version.
 *
 * Hopsworks is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 * PURPOSE.  See the GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License along with this program.
 * If not, see <https://www.gnu.org/licenses/>.
 */

package io.hops.hopsworks.common.featurestore.featuremonitoring.config;

import com.fasterxml.jackson.annotation.JsonTypeName;
import io.hops.hopsworks.common.api.RestDTO;
import io.hops.hopsworks.common.featurestore.featuremonitoring.monitoringwindowconfiguration.MonitoringWindowConfigurationDTO;
import io.hops.hopsworks.common.jobs.scheduler.JobScheduleV2DTO;
import io.hops.hopsworks.persistence.entity.featurestore.featuremonitoring.config.FeatureMonitoringType;
import lombok.Getter;
import lombok.Setter;

@JsonTypeName("featureMonitoringConfigurationDTO")
@Getter
@Setter
public class FeatureMonitoringConfigurationDTO extends RestDTO<FeatureMonitoringConfigurationDTO> {
  
  private Integer featureStoreId;
  private String name;
  private String description;
  private String featureName;
  private Integer id;
  private FeatureMonitoringType featureMonitoringType;
  
  private Integer featureGroupId;
  private String featureViewName;
  private Integer featureViewVersion;
  
  private DescriptiveStatisticsComparisonConfigurationDTO statisticsComparisonConfig;
  private MonitoringWindowConfigurationDTO detectionWindowConfig;
  private MonitoringWindowConfigurationDTO referenceWindowConfig;
  
  // Integration with other Hopsworks services
  private JobScheduleV2DTO jobSchedule;
  private String jobName;
}