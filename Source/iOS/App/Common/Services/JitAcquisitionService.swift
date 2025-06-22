// Copyright 2022 DolphiniOS Project
// SPDX-License-Identifier: GPL-2.0-or-later

import UIKit

class JitAcquisitionService : UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    let manager = JitManager.shared()
    
    manager.recheckIfJitIsAcquired()
    
    if (!manager.acquiredJit) {
      manager.acquireJitByPTrace()

#if NONJAILBROKEN
      manager.acquireJitByAltServer()
#endif
    }

    // Execute a small JIT-ed function to verify that code execution works.
    let result = JitTest.execute { value in
      NSLog("JIT received results: \(value)")
    }

    if result == 0 {
      NSLog("JIT execution completed successfully")
    } else {
      NSLog("JIT execution failed with code: \(result)")
    }

    return true
  }
}

private let REGION_SIZE: Int32 = 0x4000 * 1

private func printiOSVersionAndDevice() {
  let systemVersion = UIDevice.current.systemVersion

  var systemInfo = utsname()
  uname(&systemInfo)
  let capacity = MemoryLayout.size(ofValue: systemInfo.machine)
  let deviceModel = withUnsafePointer(to: &systemInfo.machine) {
    $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
      String(cString: $0)
    }
  }

  print("iOS Version: \(systemVersion)")
  print("Device Model: \(deviceModel)")
}

private func writeInstructions(to page: UnsafeMutableRawPointer) {
  let instructions: [UInt32] = [
    0x52800540, // mov w0, #42
    0xD65F03C0  // ret
  ]

  instructions.withUnsafeBufferPointer { buffer in
    let size = buffer.count * MemoryLayout<UInt32>.size
    page.copyMemory(from: buffer.baseAddress!, byteCount: size)
  }
}

private struct JitTest {
  static func execute(callback: @escaping (Int32) -> Void) -> Int32 {
    guard let page = mmap(
      nil,
      Int(REGION_SIZE),
      PROT_READ | PROT_EXEC,
      MAP_ANON | MAP_PRIVATE,
      -1,
      0
    ), page != MAP_FAILED else {
      print("Failed to mmap memory")
      return 1
    }

    let bufRW = vm_address_t(UInt(bitPattern: page))
    var bufRX: vm_address_t = 0
    var curProt: vm_prot_t = 0
    var maxProt: vm_prot_t = 0

    let remapResult = vm_remap(
      mach_task_self_,
      &bufRX,
      vm_size_t(REGION_SIZE),
      0,
      VM_FLAGS_ANYWHERE,
      mach_task_self_,
      bufRW,
      0,
      &curProt,
      &maxProt,
      VM_INHERIT_NONE
    )

    if remapResult != KERN_SUCCESS {
      print("Failed to remap RX region: \(remapResult)")
      munmap(page, Int(REGION_SIZE))
      return 1
    }

    let protectRXResult = vm_protect(
      mach_task_self_,
      bufRX,
      vm_size_t(REGION_SIZE),
      0,
      VM_PROT_READ | VM_PROT_EXECUTE
    )

    if protectRXResult != KERN_SUCCESS {
      print("Failed to set RX protection: \(protectRXResult)")
      vm_deallocate(mach_task_self_, bufRX, vm_size_t(REGION_SIZE))
      munmap(page, Int(REGION_SIZE))
      return 1
    }

    let protectRWResult = vm_protect(
      mach_task_self_,
      bufRW,
      vm_size_t(REGION_SIZE),
      0,
      VM_PROT_READ | VM_PROT_WRITE
    )

    if protectRWResult != KERN_SUCCESS {
      print("Failed to set RW protection: \(protectRWResult)")
      vm_deallocate(mach_task_self_, bufRX, vm_size_t(REGION_SIZE))
      munmap(page, Int(REGION_SIZE))
      return 1
    }

    printiOSVersionAndDevice()

    let rwPointer = UnsafeMutableRawPointer(bitPattern: UInt(bufRW))!
    writeInstructions(to: rwPointer)

    let funcPointer = UnsafeRawPointer(bitPattern: UInt(bufRX))!
    let point = unsafeBitCast(funcPointer, to: (@convention(c) () -> Int32).self)

    let result = point()
    print("Executed JIT-ed function, result: \(result)")

    callback(result)

    vm_deallocate(mach_task_self_, bufRX, vm_size_t(REGION_SIZE))
    munmap(page, Int(REGION_SIZE))

    return 0
  }
}
