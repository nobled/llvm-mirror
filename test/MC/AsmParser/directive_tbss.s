# RUN: llvm-mc -triple i386-unknown-unknown %s | FileCheck %s

# CHECK: .tbss _a$tlv$init, 4
# CHECK: .tbss _b$tlv$init, 4, 3

.tbss _a$tlv$init, 4
.tbss _b$tlv$init, 4, 3