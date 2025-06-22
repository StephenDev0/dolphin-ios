// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <cstddef>
#include <map>
#include <mutex>

namespace Common
{
class JITMemoryTracker final
{
public:
  JITMemoryTracker();

  void RegisterJITRegion(void* rx_ptr, void* rw_ptr, size_t size);
  void UnregisterJITRegion(void* ptr);

  void JITRegionWriteEnableExecuteDisable(void* ptr);
  void JITRegionWriteDisableExecuteEnable(void* ptr);

private:
  struct JITRegionInfo
  {
    void* rx_ptr;
    void* rw_ptr;
    size_t size;
    int nest_counter;
  };

  JITRegionInfo* FindRegion(void* ptr);

  std::map<void*, JITRegionInfo> m_jit_regions;
  std::mutex m_mutex;
};
}
