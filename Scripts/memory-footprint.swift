import Darwin
import Foundation

guard CommandLine.arguments.count == 2,
      let processID = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: memory-footprint <pid>\n".utf8))
    exit(2)
}

var usage = rusage_info_v4()
let result = withUnsafeMutablePointer(to: &usage) { usagePointer in
    let buffer = UnsafeMutableRawPointer(usagePointer)
        .assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
    return proc_pid_rusage(processID, RUSAGE_INFO_V4, buffer)
}

guard result == 0 else {
    FileHandle.standardError.write(Data("could not read physical footprint for pid \(processID)\n".utf8))
    exit(1)
}

print(usage.ri_phys_footprint)
