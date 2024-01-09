-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local window_shade_defaults = require "st.zigbee.defaults.windowShade_defaults"
local WindowCovering = zcl_clusters.WindowCovering
local PowerConfiguration = zcl_clusters.PowerConfiguration

local SHADE_SET_STATUS = "shade_set_status"

local is_smartwings_window_shade = function(opts, driver, device)
  if device:get_manufacturer() == "Smartwings" then
    return true
  end
  return false
end

local function current_position_attr_handler(driver, device, value, zb_rx)
  print("<<<< Subdriver Smartwings: current_position_attr_handler")
  local level = 100 - value.value
  local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
  local windowShade = capabilities.windowShade.windowShade
  if level == 0 then
    device:emit_event(windowShade.closed())
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(0))
  elseif level == 100 then
    device:emit_event(windowShade.open())
    device:emit_event(capabilities.windowShadeLevel.shadeLevel(100))
  else
    if current_level ~= level or current_level == nil then
      current_level = current_level or 0
      device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
      local event = nil
      if current_level ~= level then
        event = current_level < level and windowShade.opening() or windowShade.closing()
      end
      if event ~= nil then
        device:emit_event(event)
      end
    end
    local set_status_timer = device:get_field(SHADE_SET_STATUS)
    if set_status_timer then
      device.thread:cancel_timer(set_status_timer)
      device:set_field(SHADE_SET_STATUS, nil)
    end
    local set_window_shade_status = function()
      local current_level = device:get_latest_state("main", capabilities.windowShadeLevel.ID, capabilities.windowShadeLevel.shadeLevel.NAME)
      if current_level == 0 then
        device:emit_event(windowShade.closed())
      elseif current_level == 100 then
        device:emit_event(windowShade.open())
      else
        device:emit_event(windowShade.partially_open())
      end
    end
    set_status_timer = device.thread:call_with_delay(2, set_window_shade_status)
    device:set_field(SHADE_SET_STATUS, set_status_timer)
  end
end

local function set_window_shade_level_close(driver, device, cmd)
  print("<<<<< smartwings subdriver: set_window_shade_level_close >>>")
  local level = 100
    print("<<< level sent", level)
    device:send_to_component(cmd.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function set_window_shade_level_open(driver, device, cmd)
  print("<<<<< smartwings subdriver: set_window_shade_level_open >>>")
  local level = 0
    print("<<< level sent", level)
    device:send_to_component(cmd.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

local function window_shade_level_cmd_handler(driver, device, cmd)
  print("<<<<< smartwings subdriver: window_shade_level_cmd_handler >>>")
  local level = 100 - cmd.args.shadeLevel
  device:send_to_component(cmd.component, WindowCovering.server.commands.GoToLiftPercentage(device, level))
end

-- battery percentage
local function battery_perc_attr_handler(driver, device, value, zb_rx)
  -- this device use battery without / 2
  device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value, capabilities.battery.battery(value.value))
end

local smartwings_window_shade = {
  NAME = "smartwings window shade",
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = set_window_shade_level_open,
      [capabilities.windowShade.commands.close.NAME] = set_window_shade_level_close,
    },
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = window_shade_level_cmd_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [WindowCovering.ID] = {
        [WindowCovering.attributes.CurrentPositionLiftPercentage.ID] = current_position_attr_handler
      },
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryPercentageRemaining.ID] = battery_perc_attr_handler,
      }
    }
  },
  can_handle = is_smartwings_window_shade
}

return smartwings_window_shade
