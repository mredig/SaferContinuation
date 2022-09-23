# SaferContinuation

This is meant to make porting async/await from older methods even safer by providing some mechanisms around Continuations communicating when failure occurs.

It is either entirely unecessary or fills in some gaps (I'm aware of the `Unsafe` and `Checked`-`Continuation` types, but `CheckedContinuation` seemingly leaves some things to be desired in my opinion) and provides some assistance while migrating code to async/await and includes some troubleshooting tools. 

I'm certain that it adds a non-trivial amount of overhead (to async code), but should allow for safer migration from older async code. I have not tested to compare performance metrics between this and the existing types.
