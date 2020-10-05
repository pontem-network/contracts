module 00000000.Record {
resource T {
	age: u8
}
public loop_increment_1(loc0: &signer) {
B0:
	0: CopyLoc[0](Arg0: &signer)
	1: Call[0](address_of(&signer): address)
	2: MoveFrom[0](T)
	3: StLoc[2](loc0: T)
B1:
	4: CopyLoc[1](Arg1: u8)
	5: LdU8(0)
	6: Gt
	7: BrTrue(9)
B2:
	8: Branch(22)
B3:
	9: CopyLoc[1](Arg1: u8)
	10: LdU8(1)
	11: Sub
	12: StLoc[1](Arg1: u8)
	13: ImmBorrowLoc[2](loc0: T)
	14: ImmBorrowField[0](T.age: u8)
	15: ReadRef
	16: LdU8(1)
	17: Add
	18: MutBorrowLoc[2](loc0: T)
	19: MutBorrowField[0](T.age: u8)
	20: WriteRef
	21: Branch(4)
B4:
	22: MoveLoc[0](Arg0: &signer)
	23: MoveLoc[2](loc0: T)
	24: MoveTo[0](T)
	25: Ret
}
}
