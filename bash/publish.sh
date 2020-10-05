MY_GUY=wallet12tg20s9g4les55vfvnumlkg0a5zk825py9j0ha

function publish_module () {
    dncli q vm compile $1 $MY_GUY --to-file out/$1.json;
    dncli tx vm publish out/$1.json --from $MY_GUY --fees 100000dfi --gas 500000;
}

publish_module modules/Auction.move
sleep 10;
publish_module modules/CDP.move
