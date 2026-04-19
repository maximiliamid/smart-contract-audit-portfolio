//////////////////////////////////////////////////////////////////////////////
// Test cases for the Treasure Hunt circuit.
/////////////////////////////////////////////////////////////////////////////

use crate::main;
use crate::ALLOWED_TREASURE_HASHES;
use crate::is_allowed;


// Test one of the allowed treasures and its corresponding hash to ensure
// the circuit accepts valid inputs.
#[test]
fn test_treasure_hunt_one_treasure_success() {
    // Test with a valid treasure and its hash.
    let treasure: Field = 1;
    // pedersen_hash([1])
    let treasure_hash: Field = 1505662313093145631275418581390771847921541863527840230091007112166041775502; 
    let recipient: Field = 2; // Dummy recipient address as a Field. 

    // Call the main function with the test inputs.
    main(treasure, treasure_hash, recipient);
}


// Test all allowed treasures and their corresponding hashes to ensure
// the circuit accepts all valid inputs.
#[test]
fn test_treasure_hunt_all_treasures_success() {

    let treasures: [Field; 10] = [1, 2, 3, 4, 5, 6, 7, 8, 10, 10];
    for i in 0..10 {
        let treasure = treasures[i];
        let treasure_hash = ALLOWED_TREASURE_HASHES[i];
        let recipient: Field = 2; // Dummy recipient address as a Field. 

        // Call the main function with the test inputs.
        main(treasure, treasure_hash, recipient);
    }
}
            

// Test with an invalid treasure that does not correspond to any allowed hash to ensure
// the circuit correctly rejects invalid inputs.
#[test(should_fail)]
fn test_treasure_hunt_invalid_treasure_fail() {
   
    let treasure: Field = 42;
    // pedersen_hash([42])
    let treasure_hash: Field = 8913516862598573296435442855815114781437751728843870842892032683248661440805;
    assert(std::hash::pedersen_hash([treasure]) == treasure_hash);
    let recipient: Field = 3; // Dummy recipient address as a Field. 

    // Call the main function with the test inputs.
    // This should fail because the hash is not in the allowed set
    main(treasure, treasure_hash, recipient);
}


// Test with a valid treasure but an incorrect hash to ensure
// the circuit correctly rejects inputs where the hash does not match the treasure.
#[test(should_fail)]
fn test_treasure_hunt_mismatched_hash_fail() {
    // Valid treasure corresponding to the first allowed hash.
    let treasure: Field = 1; 
     // Hash of treasure 5, not treasure 1.
    let treasure_hash: Field = 10311210168613568792124008431580767227982446451742366771285792060556636004770;
    let recipient: Field = 4; // Dummy recipient address as a Field. 

    // Call the main function with the test inputs.
    // This should fail because the hash does not match the treasure.
    main(treasure, treasure_hash, recipient);
}  


// Test is_allowed function directly to ensure it correctly identifies allowed and disallowed hashes.
#[test]
fn test_is_allowed_function() {
        assert(is_allowed(ALLOWED_TREASURE_HASHES[0]) == true);         
}
    