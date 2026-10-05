/'
    Project: fblint regression
    File: actual_boundary_review.bas
    Purpose: preserve real external-layout and environment review findings.
    Responsibilities: exercise the unchanged ABI rule and an actual ENVIRON call.
    This file is intentionally unsafe review input, not production code.
'/
Type BinaryPacket
    value As Integer
End Type
Dim As String value = Environ("FBLINT_UNSET_TEST_VARIABLE")
Print value
/' end of actual_boundary_review.bas '/
