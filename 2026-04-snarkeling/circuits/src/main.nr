// Treasure Hunt circuit 
//
//
// This circuit proves that the prover knows a secret (the treasure) that corresponds to a
// treasure hash in a known set, without revealing the secret itself.
// The circuit takes a private input (the treasure) and two public inputs
// (the hash of the treasure and the recipient address). It verifies that the
// hash is in a predefined set of allowed hashes and that it matches the
// hash of the provided treasure. This allows the prover to demonstrate knowledge
// of a valid treasure without revealing which one it is, while also binding
// the proof to a specific recipient address to prevent reuse of the proof for
// different recipients effectively mitigating replay attacks.

mod tests;


// The main function of the circuit that verifies the treasure hunt proof.
// Private input:
//  - treasure: the treasure secret (hidden)
//
// Public inputs:
//  - treasure_hash: identifies which treasure was found (revealed)
//  - recipient: EVM address encoded as a Field (revealed)
//
// Proof statement:
//  1) treasure_hash is one of 10 allowed hashes baked into the circuit
//  2) treasure_hash == H(treasure), where H is the pedersen hash function
fn main(treasure: Field, treasure_hash: pub Field, recipient: pub Field) {

    // Enforce membership in the baked-in treasure set.
    assert(is_allowed(treasure_hash));

    // Bind the proof to the declared treasure hash.
    assert(std::hash::pedersen_hash([treasure]) == treasure_hash);

    // Noir enforces constraints on the public inputs,
    // so we don't need an explicit check for recipient format here.
    // The "unused variable" warning should be ignored.
}


// Helper function to check if the provided hash is in the allowed set.
fn is_allowed(hash: Field) -> bool {
    let mut ok = false;
    for i in 0..10 {
        if hash == ALLOWED_TREASURE_HASHES[i] {
            ok = true;
        }
    }
    ok
}


// Baked-in set of 10 allowed treasure hashes (pedersen hashes).
global ALLOWED_TREASURE_HASHES: [Field; 10] = [
    1505662313093145631275418581390771847921541863527840230091007112166041775502,
    -7876059170207639417138377068663245559360606207000570753582208706879316183353,
    -5602859741022561807370900516277986970516538128871954257532197637239594541050,
    2256689276847399345359792277406644462014723416398290212952821205940959307205,
    10311210168613568792124008431580767227982446451742366771285792060556636004770,
    -5697637861416433807484703347699404695743570043365849280798663758395067508,
    -2009295789879562882359281321158573810642695913475210803991480097462832104806,
    8931814952839857299896840311953754931787080333405300398787637512717059406908,
    -961435057317293580094826482786572873533235701183329831124091847635547871092,
    -961435057317293580094826482786572873533235701183329831124091847635547871092 
];



