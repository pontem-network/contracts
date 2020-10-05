MY_GUY=wallet12tg20s9g4les55vfvnumlkg0a5zk825py9j0ha

function run_script () {

    file=$1;
    shift;

    echo "dncli q vm compile $file $MY_GUY --to-file out/$file.json --from $MY_GUY"
    echo "dncli tx vm execute out/$file.json $@ $MY_GUY --fees 100000dfi --gas 500000 --from $MY_GUY"

    dncli q vm compile $file $MY_GUY --to-file out/$file.json;
    dncli tx vm execute out/$file.json $@ --fees 100000dfi --gas 500000 --from $MY_GUY;
}

# run_script scripts/01_lender_create_offer.move 106 103;
run_script scripts/02_borrower_take_offer.move $MY_GUY;
