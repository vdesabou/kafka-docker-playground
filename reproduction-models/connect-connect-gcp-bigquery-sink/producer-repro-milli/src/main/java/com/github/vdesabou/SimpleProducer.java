package com.github.vdesabou;

import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.clients.admin.CreateTopicsResult;
import org.apache.kafka.clients.admin.KafkaAdminClient;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.Producer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.config.TopicConfig;
import org.apache.kafka.common.errors.TopicExistsException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.time.LocalDateTime;
import java.util.Collections;
import java.util.Map;
import java.util.Properties;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;
import com.github.vdesabou.Customer;

import uk.co.jemos.podam.api.PodamFactoryImpl;
import uk.co.jemos.podam.api.PodamFactory;
import org.jeasy.random.EasyRandom;
import org.jeasy.random.EasyRandomParameters;
import java.nio.charset.Charset;
import com.github.javafaker.Faker;

public class SimpleProducer {

    private static final String KAFKA_ENV_PREFIX = "KAFKA_";
    private final Logger logger = LoggerFactory.getLogger(SimpleProducer.class);
    private final Properties properties;
    private final String topicName;
    private final Long messageBackOff;
    private Long nbMessages;

    public static void main(String[] args) throws InterruptedException, ExecutionException {
        SimpleProducer simpleProducer = new SimpleProducer();
        simpleProducer.start();
    }

    public SimpleProducer() throws ExecutionException, InterruptedException {
        properties = buildProperties(defaultProps, System.getenv(), KAFKA_ENV_PREFIX);
        topicName = System.getenv().getOrDefault("TOPIC", "sample");
        messageBackOff = Long.valueOf(System.getenv().getOrDefault("MESSAGE_BACKOFF", "100"));

        final Integer numberOfPartitions = Integer.valueOf(System.getenv().getOrDefault("NUMBER_OF_PARTITIONS", "2"));
        final Short replicationFactor = Short.valueOf(System.getenv().getOrDefault("REPLICATION_FACTOR", "3"));
        nbMessages = Long.valueOf(System.getenv().getOrDefault("NB_MESSAGES", "10"));
        if(nbMessages == -1) {
            nbMessages = Long.MAX_VALUE;
        }

        AdminClient adminClient = KafkaAdminClient.create(properties);
        createTopic(adminClient, topicName, numberOfPartitions, replicationFactor);
    }

    private void start() throws InterruptedException {
        logger.info("creating producer with props: {}", properties);

        logger.info("Sending data to `{}` topic", topicName);
        Faker faker = new Faker();
        // // PodamFactory factory = new PodamFactoryImpl();
        // EasyRandomParameters parameters = new EasyRandomParameters()
        //         // .seed(123L)
        //         .objectPoolSize(10)
        //         .randomizationDepth(10)
        //         .stringLengthRange(1, 30)
        //         .collectionSizeRange(1, 10)
        //         .scanClasspathForConcreteTypes(true)
        //         .overrideDefaultInitialization(false)
        //         .ignoreRandomizationErrors(false);
        // EasyRandom generator = new EasyRandom(parameters);

        try (Producer<Long, Customer> producer = new KafkaProducer<>(properties)) {
            long id = 0;
            while (id < nbMessages) {

                // This will use constructor with minimum arguments and
                // then setters to populate POJO
                // Customer customer = factory.manufacturePojo(Customer.class);

                //Customer customer = generator.nextObject(Customer.class);

              Customer customer = Customer.newBuilder()
                .setCount(id)
                .setFirstName("㑥㑦㑧㑨㑩㑪㑫㑬㑭㑮㑯㑰㑱㑲㑳㑴㑵㑶㑷㑸㑹㑺㑻㑼㑽㑾㑿㒀㒁㒂㒃㒄㒅㒆㒇㒈㒉㒊㒋㒌㒍㒎㒏㒐㒑㒒㒓㒔㒕㒖㒗㒘㒙㒚㒛㒜㒝㒞㒟㒠㒡㒢㒣㒤㒥㒦㒧㒨㒩㒪㒫㒬㒭㒮㒯㒰㒱㒲㒳㒴㒵㒶㒷㒸㒹㒺㒻㒼㒽㒾㒿㓀㓁㓂㓃㓄㓅㓆㓇㓈㓉㓊㓋㓌㓍㓎㓏㓐㓑㓒㓓㓔㓕㓖㓗㓘㓙㓚㓛㓜㓝㓞㓟㓠㓡㓢㓣㓤㓥㓦㓧㓨㓩㓪㓫㓬㓭㓮㓯㓰㓱㓲㓳㓴㓵㓶㓷㓸㓹㓺㓻㓼㓽㓾㓿㔀㔁㔂㔃㔄㔅㔆㔇㔈㔉㔊㔋㔌㔍㔎㔏㔐㔑㔒㔓㔔㔕㔖㔗㔘㔙㔚㔛㔜㔝㔞㔟㔠㔡㔢㔣㔤㔥㔦㔧㔨㔩㔪㔫㔬㔭㔮㔯㔰㔱㔲㔳㔴㔵㔶㔷㔸㔹㔺㔻㔼㔽㔾㔿㕀㕁㕂㕃㕄㕅㕆㕇㕈㕉㕊㕋㕌㕍㕎㕏㕐㕑㕒㕓㕔㕕㕖㕗㕘㕙㕚㕛㕜㕝㕞㕟㕠㕡㕢㕣㕤㕥㕦㕧㕨㕩㕪㕫㕬㕭㕮㕯㕰㕱㕲㕳㕴㕵㕶㕷㕸㕹㕺㕻㕼㕽㕾㕿㖀㖁㖂㖃㖄㖅㖆㖇㖈㖉㖊㖋㖌㖍㖎㖏㖐㖑㖒㖓㖔㖕㖖㖗㖘㖙㖚㖛㖜㖝㖞㖟㖠㖡㖢㖣㖤㖥㖦㖧㖨㖩㖪㖫㖬㖭㖮㖯㖰㖱㖲㖳㖴㖵㖶㖷㖸㖹㖺㖻㖼㖽㖾㖿㗀㗁㗂㗃㗄㗅㗆㗇㗈㗉㗊㗋㗌㗍㗎㗏㗐㗑㗒㗓㗔㗕㗖㗗㗘㗙㗚㗛㗜㗝㗞㗟㗠㗡㗢㗣㗤㗥㗦㗧㗨㗩㗪㗫㗬㗭㗮㗯㗰㗱㗲㗳㗴㗵㗶㗷㗸㗹㗺㗻㗼㗽㗾㗿㘀㘁㘂㘃㘄㘅㘆㘇㘈㘉㘊㘋㘌㘍㘎㘏㘐㘑㘒㘓㘔㘕㘖㘗㘘㘙㘚㘛㘜㘝㘞㘟㘠㘡㘢㘣㘤㘥㘦㘧㘨㘩㘪㘫㘬㘭㘮㘯㘰㘱㘲㘳㘴㘵㘶㘷㘸㘹㘺㘻㘼㘽㘾㘿㙀㙁㙂㙃㙄㙅㙆㙇㙈㙉㙊㙋㙌㙍㙎㙏㙐㙑㙒㙓㙔㙕㙖㙗㙘㙙㙚㙛㙜㙝㙞㙟㙠㙡㙢㙣㙤㙥㙦㙧㙨㙩㙪㙫㙬㙭㙮㙯㙰㙱㙲㙳㙴㙵㙶㙷㙸㙹㙺㙻㙼㙽㙾㙿㚀㚁㚂㚃㚄㚅㚆㚇㚈㚉㚊㚋㚌㚍㚎㚏㚐㚑㚒㚓㚔㚕㚖㚗㚘㚙㚚㚛㚜㚝㚞㚟㚠㚡㚢㚣㚤㚥㚦㚧㚨㚩㚪㚫㚬㚭㚮㚯㚰㚱㚲㚳㚴㚵㚶㚷㚸㚹㚺㚻㚼㚽㚾㚿㛀㛁㛂㛃㛄㛅㛆㛇㛈㛉㛊㛋㛌㛍㛎㛏㛐㛑㛒㛓㛔㛕㛖㛗㛘㛙㛚㛛㛜㛝㛞㛟㛠㛡㛢㛣㛤㛥㛦㛧㛨㛩㛪㛫㛬㛭㛮㛯㛰㛱㛲㛳㛴㛵㛶㛷㛸㛹㛺㛻㛼㛽㛾㛿㜀㜁㜂㜃㜄㜅㜆㜇㜈㜉㜊㜋㜌㜍㜎㜏㜐㜑㜒㜓㜔㜕㜖㜗㜘㜙㜚㜛㜜㜝㜞㜟㜠㜡㜢㜣㜤㜥㜦㜧㜨㜩㜪㜫㜬㜭㜮㜯㜰㜱㜲㜳㜴㜵㜶㜷㜸㜹㜺㜻㜼㜽㜾㜿㝀㝁㝂㝃㝄㝅㝆㝇㝈㝉㝊㝋㝌㝍㝎㝏㝐㝑㝒㝓㝔㝕㝖㝗㝘㝙㝚㝛㝜㝝㝞㝟㝠㝡㝢㝣㝤㝥㝦㝧㝨㝩㝪㝫㝬㝭㝮㝯㝰㝱㝲㝳㝴㝵㝶㝷㝸㝹㝺㝻㝼㝽㝾㝿㞀㞁㞂㞃㞄㞅㞆㞇㞈㞉㞊㞋㞌㞍㞎㞏㞐㞑㞒㞓㞔㞕㞖㞗㞘㞙㞚㞛㞜㞝㞞㞟㞠㞡㞢㞣㞤㞥㞦㞧㞨㞩㞪㞫㞬㞭㞮㞯㞰㞱㞲㞳㞴㞵㞶㞷㞸㞹㞺㞻㞼㞽㞾㞿㟀㟁㟂㟃㟄㟅㟆㟇㟈㟉㟊㟋㟌㟍㟎㟏㟐㟑㟒㟓㟔㟕㟖㟗㟘㟙㟚㟛㟜㟝㟞㟟㟠㟡㟢㟣㟤㟥㟦㟧㟨㟩㟪㟫㟬㟭㟮㟯㟰㟱㟲㟳㟴㟵㟶㟷㟸㟹㟺㟻㟼㟽㟾㟿㠀㠁㠂㠃㠄㠅㠆㠇㠈㠉㠊㠋㠌㠍㠎㠏㠐㠑㠒㠓㠔㠕㠖㠗㠘㠙㠚㠛㠜㠝㠞㠟㠠㠡㠢㠣㠤㠥㠦㠧㠨㠩㠪㠫㠬㠭㠮㠯㠰㠱㠲㠳㠴㠵㠶㠷㠸㠹㠺㠻㠼㠽㠾㠿㡀㡁㡂㡃㡄㡅㡆㡇㡈㡉㡊㡋㡌㡍㡎㡏㡐㡑㡒㡓㡔㡕㡖㡗㡘㡙㡚㡛㡜㡝㡞㡟㡠㡡㡢㡣㡤㡥㡦㡧㡨㡩㡪㡫㡬㡭㡮㡯㡰㡱㡲㡳㡴㡵㡶㡷㡸㡹㡺㡻㡼㡽㡾㡿㢀㢁㢂㢃㢄㢅㢆㢇㢈㢉㢊㢋㢌㢍㢎㢏㢐㢑㢒㢓㢔㢕㢖㢗㢘㢙㢚㢛㢜㢝㢞㢟㢠㢡㢢㢣㢤㢥㢦㢧㢨㢩㢪㢫㢬㢭㢮㢯㢰㢱㢲㢳㢴㢵㢶㢷㢸㢹㢺㢻㢼㢽㢾㢿㣀㣁㣂㣃㣄㣅㣆㣇㣈㣉㣊㣋㣌㣍㣎㣏㣐㣑㣒㣓㣔㣕㣖㣗㣘㣙㣚㣛㣜㣝㣞㣟㣠㣡㣢㣣㣤㣥㣦㣧㣨㣩㣪㣫㣬㣭㣮㣯㣰㣱㣲㣳㣴㣵㣶㣷㣸㣹㣺㣻㣼㣽㣾㣿㤀㤁㤂㤃㤄㤅㤆㤇㤈㤉㤊㤋㤌㤍㤎㤏㤐㤑㤒㤓㤔㤕㤖㤗㤘㤙㤚㤛㤜㤝㤞㤟㤠㤡㤢㤣㤤㤥㤦㤧㤨㤩㤪㤫㤬㤭㤮㤯㤰㤱㤲㤳㤴㤵㤶㤷㤸㤹㤺㤻㤼㤽㤾㤿㥀㥁㥂㥃㥄㥅㥆㥇㥈㥉㥊㥋㥌㥍㥎㥏㥐㥑㥒㥓㥔㥕㥖㥗㥘㥙㥚㥛㥜㥝㥞㥟㥠㥡㥢㥣㥤㥥㥦㥧㥨㥩㥪㥫㥬㥭㥮㥯㥰㥱㥲㥳㥴㥵㥶㥷㥸㥹㥺㥻㥼㥽㥾㥿㦀㦁㦂㦃㦄㦅㦆㦇㦈㦉㦊㦋㦌㦍㦎㦏㦐㦑㦒㦓㦔㦕㦖㦗㦘㦙㦚㦛㦜㦝㦞㦟㦠㦡㦢㦣㦤㦥㦦㦧㦨㦩㦪㦫㦬㦭㦮㦯㦰㦱㦲㦳㦴㦵㦶㦷㦸㦹㦺㦻㦼㦽㦾㦿㧀㧁㧂㧃㧄㧅㧆㧇㧈㧉㧊㧋㧌㧍㧎㧏㧐㧑㧒㧓㧔㧕㧖㧗㧘㧙㧚㧛㧜㧝㧞㧟㧠㧡㧢㧣㧤㧥㧦㧧㧨㧩㧪㧫㧬㧭㧮㧯㧰㧱㧲㧳㧴㧵㧶㧷㧸㧹㧺㧻㧼㧽㧾㧿㨀㨁㨂㨃㨄㨅㨆㨇㨈㨉㨊㨋㨌㨍㨎㨏㨐㨑㨒㨓㨔㨕㨖㨗㨘㨙㨚㨛㨜㨝㨞㨟㨠㨡㨢㨣㨤㨥㨦㨧㨨㨩㨪㨫㨬㨭㨮㨯㨰㨱㨲㨳㨴㨵㨶㨷㨸㨹㨺㨻㨼㨽㨾㨿㩀㩁㩂㩃㩄㩅㩆㩇㩈㩉㩊㩋㩌㩍㩎㩏㩐㩑㩒㩓㩔㩕㩖㩗㩘㩙㩚㩛㩜㩝㩞㩟㩠㩡㩢㩣㩤㩥㩦㩧㩨㩩㩪㩫㩬㩭㩮㩯㩰㩱㩲㩳㩴㩵㩶㩷㩸㩹㩺㩻㩼㩽㩾㩿㪀㪁㪂㪃㪄㪅㪆㪇㪈㪉㪊㪋㪌㪍㪎㪏㪐㪑㪒㪓㪔㪕㪖㪗㪘㪙㪚㪛㪜㪝㪞㪟㪠㪡㪢㪣㪤㪥㪦㪧㪨㪩㪪㪫㪬㪭㪮㪯㪰㪱㪲㪳㪴㪵㪶㪷㪸㪹㪺㪻㪼㪽㪾㪿㫀㫁㫂㫃㫄㫅㫆㫇㫈㫉㫊㫋㫌㫍㫎㫏㫐㫑㫒㫓㫔㫕㫖㫗㫘㫙㫚㫛㫜㫝㫞㫟㫠㫡㫢㫣㫤㫥㫦㫧㫨㫩㫪㫫㫬㫭㫮㫯㫰㫱㫲㫳㫴㫵㫶㫷㫸㫹㫺㫻㫼㫽㫾㫿㬀㬁㬂㬃㬄㬅㬆㬇㬈㬉㬊㬋㬌㬍㬎㬏㬐㬑㬒㬓㬔㬕㬖㬗㬘㬙㬚㬛㬜㬝㬞㬟㬠㬡㬢㬣㬤㬥㬦㬧㬨㬩㬪㬫㬬㬭㬮㬯㬰㬱㬲㬳㬴㬵㬶㬷㬸㬹㬺㬻㬼㬽㬾㬿㭀㭁㭂㭃㭄㭅㭆㭇㭈㭉㭊㭋㭌㭍㭎㭏㭐㭑㭒㭓㭔㭕㭖㭗㭘㭙㭚㭛㭜㭝㭞㭟㭠㭡㭢㭣㭤㭥㭦㭧㭨㭩㭪㭫㭬㭭㭮㭯㭰㭱㭲㭳㭴㭵㭶㭷㭸㭹㭺㭻㭼㭽㭾㭿㮀㮁㮂㮃㮄㮅㮆㮇㮈㮉㮊㮋㮌㮍㮎㮏㮐㮑㮒㮓㮔㮕㮖㮗㮘㮙㮚㮛㮜㮝㮞㮟㮠㮡㮢㮣㮤㮥㮦㮧㮨㮩㮪㮫㮬㮭㮮㮯㮰㮱㮲㮳㮴㮵㮶㮷㮸㮹㮺㮻㮼㮽㮾㮿㯀㯁㯂㯃㯄㯅㯆㯇㯈㯉㯊㯋㯌㯍㯎㯏㯐㯑㯒㯓㯔㯕㯖㯗㯘㯙㯚㯛㯜㯝㯞㯟㯠㯡㯢㯣㯤㯥㯦㯧㯨㯩㯪㯫㯬㯭㯮㯯㯰㯱㯲㯳㯴㯵㯶㯷㯸㯹㯺㯻㯼㯽㯾㯿㰀㰁㰂㰃㰄㰅㰆㰇㰈㰉㰊㰋㰌㰍㰎㰏㰐㰑㰒㰓㰔㰕㰖㰗㰘㰙㰚㰛㰜㰝㰞㰟㰠㰡㰢㰣㰤㰥㰦㰧㰨㰩㰪㰫㰬㰭㰮㰯㰰㰱㰲㰳㰴㰵㰶㰷㰸㰹㰺㰻㰼㰽㰾㰿㱀㱁㱂㱃㱄㱅㱆㱇㱈㱉㱊㱋㱌㱍㱎㱏㱐㱑㱒㱓㱔㱕㱖㱗㱘㱙㱚㱛㱜㱝㱞㱟㱠㱡㱢㱣㱤㱥㱦㱧㱨㱩㱪㱫㱬㱭㱮㱯㱰㱱㱲㱳㱴㱵㱶㱷㱸㱹㱺㱻㱼㱽㱾㱿㲀㲁㲂㲃㲄㲅㲆㲇㲈㲉㲊㲋㲌㲍㲎㲏㲐㲑㲒㲓㲔㲕㲖㲗㲘㲙㲚㲛㲜㲝㲞㲟㲠㲡㲢㲣㲤㲥㲦㲧㲨㲩㲪㲫㲬㲭㲮㲯㲰㲱㲲㲳㲴㲵㲶㲷㲸㲹㲺㲻㲼㲽㲾㲿㳀㳁㳂㳃㳄㳅㳆㳇㳈㳉㳊㳋㳌㳍㳎㳏㳐㳑㳒㳓㳔㳕㳖㳗㳘㳙㳚㳛㳜㳝㳞㳟㳠㳡㳢㳣㳤㳥㳦㳧㳨㳩㳪㳫㳬㳭㳮㳯㳰㳱㳲㳳㳴㳵㳶㳷㳸㳹㳺㳻㳼㳽㳾㳿㴀㴁㴂㴃㴄㴅㴆㴇㴈㴉㴊㴋㴌㴍㴎㴏㴐㴑㴒㴓㴔㴕㴖㴗㴘㴙㴚㴛㴜㴝㴞㴟㴠㴡㴢㴣㴤㴥㴦㴧㴨㴩㴪㴫㴬㴭㴮㴯㴰㴱㴲㴳㴴㴵㴶㴷㴸㴹㴺㴻㴼㴽㴾㴿㵀㵁㵂㵃㵄㵅㵆㵇㵈㵉㵊㵋㵌㵍㵎㵏㵐㵑㵒㵓㵔㵕㵖㵗㵘㵙㵚㵛㵜㵝㵞㵟㵠㵡㵢㵣㵤㵥㵦㵧㵨㵩㵪㵫㵬㵭㵮㵯㵰㵱㵲㵳㵴㵵㵶㵷㵸㵹㵺㵻㵼㵽㵾㵿㶀㶁㶂㶃㶄㶅㶆㶇㶈㶉㶊㶋㶌㶍㶎㶏㶐㶑㶒㶓㶔㶕㶖㶗㶘㶙㶚㶛㶜㶝㶞㶟㶠㶡㶢㶣㶤㶥㶦㶧㶨㶩㶪㶫㶬㶭㶮㶯㶰㶱㶲㶳㶴㶵㶶㶷㶸㶹㶺㶻㶼㶽㶾㶿㷀㷁㷂㷃㷄㷅㷆㷇㷈㷉㷊㷋㷌㷍㷎㷏㷐㷑㷒㷓㷔㷕㷖㷗㷘㷙㷚㷛㷜㷝㷞㷟㷠㷡㷢㷣㷤㷥㷦㷧㷨㷩㷪㷫㷬㷭㷮㷯㷰㷱㷲㷳㷴㷵㷶㷷㷸㷹㷺㷻㷼㷽㷾㷿㸀㸁㸂㸃㸄㸅㸆㸇㸈㸉㸊㸋㸌㸍㸎㸏㸐㸑㸒㸓㸔㸕㸖㸗㸘㸙㸚㸛㸜㸝㸞㸟㸠㸡㸢㸣㸤㸥㸦㸧㸨㸩㸪㸫㸬㸭㸮㸯㸰㸱㸲㸳㸴㸵㸶㸷㸸㸹㸺㸻㸼㸽㸾㸿㹀㹁㹂㹃㹄㹅㹆㹇㹈㹉㹊㹋㹌㹍㹎㹏㹐㹑㹒㹓㹔㹕㹖㹗㹘㹙㹚㹛㹜㹝㹞㹟㹠㹡㹢㹣㹤㹥㹦㹧㹨㹩㹪㹫㹬㹭㹮㹯㹰㹱㹲㹳㹴㹵㹶㹷㹸㹹㹺㹻㹼㹽㹾㹿㺀㺁㺂㺃㺄㺅㺆㺇㺈㺉㺊㺋㺌㺍㺎㺏㺐㺑㺒㺓㺔㺕㺖㺗㺘㺙㺚㺛㺜㺝㺞㺟㺠㺡㺢㺣㺤㺥㺦㺧㺨㺩㺪㺫㺬㺭㺮㺯㺰㺱㺲㺳㺴㺵㺶㺷㺸㺹㺺㺻㺼㺽㺾㺿㻀㻁㻂㻃㻄㻅㻆㻇㻈㻉㻊㻋㻌㻍㻎㻏㻐㻑㻒㻓㻔㻕㻖㻗㻘㻙㻚㻛㻜㻝㻞㻟㻠㻡㻢㻣㻤㻥㻦㻧㻨㻩㻪㻫㻬㻭㻮㻯㻰㻱㻲㻳㻴㻵㻶㻷㻸㻹㻺㻻㻼㻽㻾㻿㼀㼁㼂㼃㼄㼅㼆㼇㼈㼉㼊㼋㼌㼍㼎㼏㼐㼑㼒㼓㼔㼕㼖㼗㼘㼙㼚㼛㼜㼝㼞㼟㼠㼡㼢㼣㼤㼥㼦㼧㼨㼩㼪㼫㼬㼭㼮㼯㼰㼱㼲㼳㼴㼵㼶㼷㼸㼹㼺㼻㼼㼽㼾㼿㽀㽁㽂㽃㽄㽅㽆㽇㽈㽉㽊㽋㽌㽍㽎㽏㽐㽑㽒㽓㽔㽕㽖㽗㽘㽙㽚㽛㽜㽝㽞㽟㽠㽡㽢㽣㽤㽥㽦㽧㽨㽩㽪㽫㽬㽭㽮㽯㽰㽱㽲㽳㽴㽵㽶㽷㽸㽹㽺㽻㽼㽽㽾㽿㾀㾁㾂㾃㾄㾅㾆㾇㾈㾉㾊㾋㾌㾍㾎㾏㾐㾑㾒㾓㾔㾕㾖㾗㾘㾙㾚㾛㾜㾝㾞㾟㾠㾡㾢㾣㾤㾥㾦㾧㾨㾩㾪㾫㾬㾭㾮㾯㾰㾱㾲㾳㾴㾵㾶㾷㾸㾹㾺㾻㾼㾽㾾㾿㿀㿁㿂㿃㿄㿅㿆㿇㿈㿉㿊㿋㿌㿍㿎㿏㿐㿑㿒㿓㿔㿕㿖㿗㿘㿙㿚㿛㿜㿝㿞㿟㿠㿡㿢㿣㿤㿥㿦㿧㿨㿩㿪㿫㿬㿭㿮㿯㿰㿱㿲㿳㿴㿵㿶㿷㿸㿹㿺㿻㿼㿽㿾㿿䀀䀁䀂䀃䀄䀅䀆䀇䀈䀉䀊䀋䀌䀍䀎䀏䀐䀑䀒䀓䀔䀕䀖䀗䀘䀙䀚䀛䀜䀝䀞䀟䀠䀡䀢䀣䀤䀥䀦䀧䀨䀩䀪䀫䀬䀭䀮䀯䀰䀱䀲䀳䀴䀵䀶䀷䀸䀹䀺䀻䀼䀽䀾䀿䁀䁁䁂䁃䁄䁅䁆䁇䁈䁉䁊䁋䁌䁍䁎䁏䁐䁑䁒䁓䁔䁕䁖䁗䁘䁙䁚䁛䁜䁝䁞䁟䁠䁡䁢䁣䁤䁥䁦䁧䁨䁩䁪䁫䁬䁭䁮䁯䁰䁱䁲䁳䁴䁵䁶䁷䁸䁹䁺䁻䁼䁽䁾䁿䂀䂁䂂䂃䂄䂅䂆䂇䂈䂉䂊䂋䂌䂍䂎䂏䂐䂑䂒䂓䂔䂕䂖䂗䂘䂙䂚䂛䂜䂝䂞䂟䂠䂡䂢䂣䂤䂥䂦䂧䂨䂩䂪䂫䂬䂭䂮䂯䂰䂱䂲䂳䂴䂵䂶䂷䂸䂹䂺䂻䂼䂽䂾䂿䃀䃁䃂䃃䃄䃅䃆䃇䃈䃉䃊䃋䃌䃍䃎䃏䃐䃑䃒䃓䃔䃕䃖䃗䃘䃙䃚䃛䃜䃝䃞䃟䃠䃡䃢䃣䃤䃥䃦䃧䃨䃩䃪䃫䃬䃭䃮䃯䃰䃱䃲䃳䃴䃵䃶䃷䃸䃹䃺䃻䃼䃽䃾䃿䄀䄁䄂䄃䄄䄅䄆䄇䄈䄉䄊䄋䄌䄍䄎䄏䄐䄑䄒䄓䄔䄕䄖䄗䄘䄙䄚䄛䄜䄝䄞䄟䄠䄡䄢䄣䄤䄥䄦䄧䄨䄩䄪䄫䄬䄭䄮䄯䄰䄱䄲䄳䄴䄵䄶䄷䄸䄹䄺䄻䄼䄽䄾䄿䅀䅁䅂䅃䅄䅅䅆䅇䅈䅉䅊䅋䅌䅍䅎䅏䅐䅑䅒䅓䅔䅕䅖䅗䅘䅙䅚䅛䅜䅝䅞䅟䅠䅡䅢䅣䅤䅥䅦䅧䅨䅩䅪䅫䅬䅭䅮䅯䅰䅱䅲䅳䅴䅵䅶䅷䅸䅹䅺䅻䅼䅽䅾䅿䆀䆁䆂䆃䆄䆅䆆䆇䆈䆉䆊䆋䆌䆍䆎䆏䆐䆑䆒䆓䆔䆕䆖䆗䆘䆙䆚䆛䆜䆝䆞䆟䆠䆡䆢䆣䆤䆥䆦䆧䆨䆩䆪䆫䆬䆭䆮䆯䆰䆱䆲䆳䆴䆵䆶䆷䆸䆹䆺䆻䆼䆽䆾䆿䇀䇁䇂䇃䇄䇅䇆䇇䇈䇉䇊䇋䇌䇍䇎䇏䇐䇑䇒䇓䇔䇕䇖䇗䇘䇙䇚䇛䇜䇝䇞䇟䇠䇡䇢䇣䇤䇥䇦䇧䇨䇩䇪䇫䇬䇭䇮䇯䇰䇱䇲䇳䇴䇵䇶䇷䇸䇹䇺䇻䇼䇽䇾䇿䈀䈁䈂䈃䈄䈅䈆䈇䈈䈉䈊䈋䈌䈍䈎䈏䈐䈑䈒䈓䈔䈕䈖䈗䈘䈙䈚䈛䈜䈝䈞䈟䈠䈡䈢䈣䈤䈥䈦䈧䈨䈩䈪䈫䈬䈭䈮䈯䈰䈱䈲䈳䈴䈵䈶䈷䈸䈹䈺䈻䈼䈽䈾䈿䉀䉁䉂䉃䉄䉅䉆䉇䉈䉉䉊䉋䉌䉍䉎䉏䉐䉑䉒䉓䉔䉕䉖䉗䉘䉙䉚䉛䉜䉝䉞䉟䉠䉡䉢䉣䉤䉥䉦䉧䉨䉩䉪䉫䉬䉭䉮䉯䉰䉱䉲䉳䉴䉵䉶䉷䉸䉹䉺䉻䉼䉽䉾䉿䊀䊁䊂䊃䊄䊅䊆䊇䊈䊉䊊䊋䊌䊍䊎䊏䊐䊑䊒䊓䊔䊕䊖䊗䊘䊙䊚䊛䊜䊝䊞䊟䊠䊡䊢䊣䊤䊥䊦䊧䊨䊩䊪䊫䊬䊭䊮䊯䊰䊱䊲䊳䊴䊵䊶䊷䊸䊹䊺䊻䊼䊽䊾䊿䋀䋁䋂䋃䋄䋅䋆䋇䋈䋉䋊䋋䋌䋍䋎䋏䋐䋑䋒䋓䋔䋕䋖䋗䋘䋙䋚䋛䋜䋝䋞䋟䋠䋡䋢䋣䋤䋥䋦䋧䋨䋩䋪䋫䋬䋭䋮䋯䋰䋱䋲䋳䋴䋵䋶䋷䋸䋹䋺䋻䋼䋽䋾䋿䌀䌁䌂䌃䌄䌅䌆䌇䌈䌉䌊䌋䌌䌍䌎䌏䌐䌑䌒䌓䌔䌕䌖䌗䌘䌙䌚䌛䌜䌝䌞䌟䌠䌡䌢䌣䌤䌥䌦䌧䌨䌩䌪䌫䌬䌭䌮䌯䌰䌱䌲䌳䌴䌵䌶䌷䌸䌹䌺䌻䌼䌽䌾䌿䍀䍁䍂䍃䍄䍅䍆䍇䍈䍉䍊䍋䍌䍍䍎䍏䍐䍑䍒䍓䍔䍕䍖䍗䍘䍙䍚䍛䍜䍝䍞䍟䍠䍡䍢䍣䍤䍥䍦䍧䍨䍩䍪䍫䍬䍭䍮䍯䍰䍱䍲䍳䍴䍵䍶䍷䍸䍹䍺䍻䍼䍽䍾䍿䎀䎁䎂䎃䎄䎅䎆䎇䎈䎉䎊䎋䎌䎍䎎䎏䎐䎑䎒䎓䎔䎕䎖䎗䎘䎙䎚䎛䎜䎝䎞䎟䎠䎡䎢䎣䎤䎥䎦䎧䎨䎩䎪䎫䎬䎭䎮䎯䎰䎱䎲䎳䎴䎵䎶䎷䎸䎹䎺䎻䎼䎽䎾䎿䏀䏁䏂䏃䏄䏅䏆䏇䏈䏉䏊䏋䏌䏍䏎䏏䏐䏑䏒䏓䏔䏕䏖䏗䏘䏙䏚䏛䏜䏝䏞䏟䏠䏡䏢䏣䏤䏥䏦䏧䏨䏩䏪䏫䏬䏭䏮䏯䏰䏱䏲䏳䏴䏵䏶䏷䏸䏹䏺䏻䏼䏽䏾䏿䐀䐁䐂䐃䐄䐅䐆䐇䐈䐉䐊䐋䐌䐍䐎䐏䐐䐑䐒䐓䐔䐕䐖䐗䐘䐙䐚䐛䐜䐝䐞䐟䐠䐡䐢䐣䐤䐥䐦䐧䐨䐩䐪䐫䐬䐭䐮䐯䐰䐱䐲䐳䐴䐵䐶䐷䐸䐹䐺䐻䐼䐽䐾䐿䑀䑁䑂䑃䑄䑅䑆䑇䑈䑉䑊䑋䑌䑍䑎䑏䑐䑑䑒䑓䑔䑕䑖䑗䑘䑙䑚䑛䑜䑝䑞䑟䑠䑡䑢䑣䑤䑥䑦䑧䑨䑩䑪䑫䑬䑭䑮䑯䑰䑱䑲䑳䑴䑵䑶䑷䑸䑹䑺䑻䑼䑽䑾䑿䒀䒁䒂䒃䒄䒅䒆䒇䒈䒉䒊䒋䒌䒍䒎䒏䒐䒑䒒䒓䒔䒕䒖䒗䒘䒙䒚䒛䒜䒝䒞䒟䒠䒡䒢䒣䒤䒥䒦䒧䒨䒩䒪䒫䒬䒭䒮䒯䒰䒱䒲䒳䒴䒵䒶䒷䒸䒹䒺䒻䒼䒽䒾䒿䓀䓁䓂䓃䓄䓅䓆䓇䓈䓉䓊䓋䓌䓍䓎䓏䓐䓑䓒䓓䓔䓕䓖䓗䓘䓙䓚䓛䓜䓝䓞䓟䓠䓡䓢䓣䓤䓥䓦䓧䓨䓩䓪䓫䓬䓭䓮䓯䓰䓱䓲䓳䓴䓵䓶䓷䓸䓹䓺䓻䓼䓽䓾䓿䔀䔁䔂䔃䔄䔅䔆䔇䔈䔉䔊䔋䔌䔍䔎䔏䔐䔑䔒䔓䔔䔕䔖䔗䔘䔙䔚䔛䔜䔝䔞䔟䔠䔡䔢䔣䔤䔥䔦䔧䔨䔩䔪䔫䔬䔭䔮䔯䔰䔱䔲䔳䔴䔵䔶䔷䔸䔹䔺䔻䔼䔽䔾䔿䕀䕁䕂䕃䕄䕅䕆䕇䕈䕉䕊䕋䕌䕍䕎䕏䕐䕑䕒䕓䕔䕕䕖䕗䕘䕙䕚䕛䕜䕝䕞䕟䕠䕡䕢䕣䕤䕥䕦䕧䕨䕩䕪䕫䕬䕭䕮䕯䕰䕱䕲䕳䕴䕵䕶䕷䕸䕹䕺䕻䕼䕽䕾䕿䖀䖁䖂䖃䖄䖅䖆䖇䖈䖉䖊䖋䖌䖍䖎䖏䖐䖑䖒䖓䖔䖕䖖䖗䖘䖙䖚䖛䖜䖝䖞䖟䖠䖡䖢䖣䖤䖥䖦䖧䖨䖩䖪䖫䖬䖭䖮䖯䖰䖱䖲䖳䖴䖵䖶䖷䖸䖹䖺䖻䖼䖽䖾䖿䗀䗁䗂䗃䗄䗅䗆䗇䗈䗉䗊䗋䗌䗍䗎䗏䗐䗑䗒䗓䗔䗕䗖䗗䗘䗙䗚䗛䗜䗝䗞䗟䗠䗡䗢䗣䗤䗥䗦䗧䗨䗩䗪䗫䗬䗭䗮䗯䗰䗱䗲䗳䗴䗵䗶䗷䗸䗹䗺䗻䗼䗽䗾䗿䘀䘁䘂䘃䘄䘅䘆䘇䘈䘉䘊䘋䘌䘍䘎䘏䘐䘑䘒䘓䘔䘕䘖䘗䘘䘙䘚䘛䘜䘝䘞䘟䘠䘡䘢䘣䘤䘥䘦䘧䘨䘩䘪䘫䘬䘭䘮䘯䘰䘱䘲䘳䘴䘵䘶䘷䘸䘹䘺䘻䘼䘽䘾䘿䙀䙁䙂䙃䙄䙅䙆䙇䙈䙉䙊䙋䙌䙍䙎䙏䙐䙑䙒䙓䙔䙕䙖䙗䙘䙙䙚䙛䙜䙝䙞䙟䙠䙡䙢䙣䙤䙥䙦䙧䙨䙩䙪䙫䙬䙭䙮䙯䙰䙱䙲䙳䙴䙵䙶䙷䙸䙹䙺䙻䙼䙽䙾䙿䚀䚁䚂䚃䚄䚅䚆䚇䚈䚉䚊䚋䚌䚍䚎䚏䚐䚑䚒䚓䚔䚕䚖䚗䚘䚙䚚䚛䚜䚝䚞䚟䚠䚡䚢䚣䚤䚥䚦䚧䚨䚩䚪䚫䚬䚭䚮䚯䚰䚱䚲䚳䚴䚵䚶䚷䚸䚹䚺䚻䚼䚽䚾䚿䛀䛁䛂䛃䛄䛅䛆䛇䛈䛉䛊䛋䛌䛍䛎䛏䛐䛑䛒䛓䛔䛕䛖䛗䛘䛙䛚䛛䛜䛝䛞䛟䛠䛡䛢䛣䛤䛥䛦䛧䛨䛩䛪䛫䛬䛭䛮䛯䛰䛱䛲䛳䛴䛵䛶䛷䛸䛹䛺䛻䛼䛽䛾䛿䜀䜁䜂䜃䜄䜅䜆䜇䜈䜉䜊䜋䜌䜍䜎䜏䜐䜑䜒䜓䜔䜕䜖䜗䜘䜙䜚䜛䜜䜝䜞䜟䜠䜡䜢䜣䜤䜥䜦䜧䜨䜩䜪䜫䜬䜭䜮䜯䜰䜱䜲䜳䜴䜵䜶䜷䜸䜹䜺䜻䜼䜽䜾䜿䝀䝁䝂䝃䝄䝅䝆䝇䝈䝉䝊䝋䝌䝍䝎䝏䝐䝑䝒䝓䝔䝕䝖䝗䝘䝙䝚䝛䝜䝝䝞䝟䝠䝡䝢䝣䝤䝥䝦䝧䝨䝩䝪䝫䝬䝭䝮䝯䝰䝱䝲䝳䝴䝵䝶䝷䝸䝹䝺䝻䝼䝽䝾䝿䞀䞁䞂䞃䞄䞅䞆䞇䞈䞉䞊䞋䞌䞍䞎䞏䞐䞑䞒䞓䞔䞕䞖䞗䞘䞙䞚䞛䞜䞝䞞䞟䞠䞡䞢䞣䞤䞥䞦䞧䞨䞩䞪䞫䞬䞭䞮䞯䞰䞱䞲䞳䞴䞵䞶䞷䞸䞹䞺䞻䞼䞽䞾䞿䟀䟁䟂䟃䟄䟅䟆䟇䟈䟉䟊䟋䟌䟍䟎䟏䟐䟑䟒䟓䟔䟕䟖䟗䟘䟙䟚䟛䟜䟝䟞䟟䟠䟡䟢䟣䟤䟥䟦䟧䟨䟩䟪䟫䟬䟭䟮䟯䟰䟱䟲䟳䟴䟵䟶䟷䟸䟹䟺䟻䟼䟽䟾䟿䠀䠁䠂䠃䠄䠅䠆䠇䠈䠉䠊䠋䠌䠍䠎䠏䠐䠑䠒䠓䠔䠕䠖䠗䠘䠙䠚䠛䠜䠝䠞䠟䠠䠡䠢䠣䠤䠥䠦䠧䠨䠩䠪䠫䠬䠭䠮䠯䠰䠱䠲䠳䠴䠵䠶䠷䠸䠹䠺䠻䠼䠽䠾䠿䡀䡁䡂䡃䡄䡅䡆䡇䡈䡉䡊䡋䡌䡍䡎䡏䡐䡑䡒䡓䡔䡕䡖䡗䡘䡙䡚䡛䡜䡝䡞䡟䡠䡡䡢䡣䡤䡥䡦䡧䡨䡩䡪䡫䡬䡭䡮䡯䡰䡱䡲䡳䡴䡵䡶䡷䡸䡹䡺䡻䡼䡽䡾䡿䢀䢁䢂䢃䢄䢅䢆䢇䢈䢉䢊䢋䢌䢍䢎䢏䢐䢑䢒䢓䢔䢕䢖䢗䢘䢙䢚䢛䢜䢝䢞䢟䢠䢡䢢䢣䢤䢥䢦䢧䢨䢩䢪䢫䢬䢭䢮䢯䢰䢱䢲䢳䢴䢵䢶䢷䢸䢹䢺䢻䢼䢽䢾䢿䣀䣁䣂䣃䣄䣅䣆䣇䣈䣉䣊䣋䣌䣍䣎䣏䣐䣑䣒䣓䣔䣕䣖䣗䣘䣙䣚䣛䣜䣝䣞䣟䣠䣡䣢䣣䣤䣥䣦䣧䣨䣩䣪䣫䣬䣭䣮䣯䣰䣱䣲䣳䣴䣵䣶䣷䣸䣹䣺䣻䣼䣽䣾䣿䤀䤁䤂䤃䤄䤅䤆䤇䤈䤉䤊䤋䤌䤍䤎䤏䤐䤑䤒䤓䤔䤕䤖䤗䤘䤙䤚䤛䤜䤝䤞䤟䤠䤡䤢䤣䤤䤥䤦䤧䤨䤩䤪䤫䤬䤭䤮䤯䤰䤱䤲䤳䤴䤵䤶䤷䤸䤹䤺䤻䤼䤽䤾䤿䥀䥁䥂䥃䥄䥅䥆䥇䥈䥉䥊䥋䥌䥍䥎䥏䥐䥑䥒䥓䥔䥕䥖䥗䥘䥙䥚䥛䥜䥝䥞䥟䥠䥡䥢䥣䥤䥥䥦䥧䥨䥩䥪䥫䥬䥭䥮䥯䥰䥱䥲䥳䥴䥵䥶䥷䥸䥹䥺䥻䥼䥽䥾䥿䦀䦁䦂䦃䦄䦅䦆䦇䦈䦉䦊䦋䦌䦍䦎䦏䦐䦑䦒䦓䦔䦕䦖䦗䦘䦙䦚䦛䦜䦝䦞䦟䦠䦡䦢䦣䦤䦥䦦䦧䦨䦩䦪䦫䦬䦭䦮䦯䦰䦱䦲䦳䦴䦵䦶䦷䦸䦹䦺䦻䦼䦽䦾䦿䧀䧁䧂䧃䧄䧅䧆䧇䧈䧉䧊䧋䧌䧍䧎䧏䧐䧑䧒䧓䧔䧕䧖䧗䧘䧙䧚䧛䧜䧝䧞䧟䧠䧡䧢䧣䧤䧥䧦䧧䧨䧩䧪䧫䧬䧭䧮䧯䧰䧱䧲䧳䧴䧵䧶䧷䧸䧹䧺䧻䧼䧽䧾䧿䨀䨁䨂䨃䨄䨅䨆䨇䨈䨉䨊䨋䨌䨍䨎䨏䨐䨑䨒䨓䨔䨕䨖䨗䨘䨙䨚䨛䨜䨝䨞䨟䨠䨡䨢䨣䨤䨥䨦䨧䨨䨩䨪䨫䨬䨭䨮䨯䨰䨱䨲䨳䨴䨵䨶䨷䨸䨹䨺䨻䨼䨽䨾䨿䩀䩁䩂䩃䩄䩅䩆䩇䩈䩉䩊䩋䩌䩍䩎䩏䩐䩑䩒䩓䩔䩕䩖䩗䩘䩙䩚䩛䩜䩝䩞䩟䩠䩡䩢䩣䩤䩥䩦䩧䩨䩩䩪䩫䩬䩭䩮䩯䩰䩱䩲䩳䩴䩵䩶䩷䩸䩹䩺䩻䩼䩽䩾䩿䪀䪁䪂䪃䪄䪅䪆䪇䪈䪉䪊䪋䪌䪍䪎䪏䪐䪑䪒䪓䪔䪕䪖䪗䪘䪙䪚䪛䪜䪝䪞䪟䪠䪡䪢䪣䪤䪥䪦䪧䪨䪩䪪䪫䪬䪭䪮䪯䪰䪱䪲䪳䪴䪵䪶䪷䪸䪹䪺䪻䪼䪽䪾䪿䫀䫁䫂䫃䫄䫅䫆䫇䫈䫉䫊䫋䫌䫍䫎䫏䫐䫑䫒䫓䫔䫕䫖䫗䫘䫙䫚䫛䫜䫝䫞䫟䫠䫡䫢䫣䫤䫥䫦䫧䫨䫩䫪䫫䫬䫭䫮䫯䫰䫱䫲䫳䫴䫵䫶䫷䫸䫹䫺䫻䫼䫽䫾䫿䬀䬁䬂䬃䬄䬅䬆䬇䬈䬉䬊䬋䬌䬍䬎䬏䬐䬑䬒䬓䬔䬕䬖䬗䬘䬙䬚䬛䬜䬝䬞䬟䬠䬡䬢䬣䬤䬥䬦䬧䬨䬩䬪䬫䬬䬭䬮䬯䬰䬱䬲䬳䬴䬵䬶䬷䬸䬹䬺䬻䬼䬽䬾䬿䭀䭁䭂䭃䭄䭅䭆䭇䭈䭉䭊䭋䭌䭍䭎䭏䭐䭑䭒䭓䭔䭕䭖䭗䭘䭙䭚䭛䭜䭝䭞䭟䭠䭡䭢䭣䭤䭥䭦䭧䭨䭩䭪䭫䭬䭭䭮䭯䭰䭱䭲䭳䭴䭵䭶䭷䭸䭹䭺䭻䭼䭽䭾䭿䮀䮁䮂䮃䮄䮅䮆䮇䮈䮉䮊䮋䮌䮍䮎䮏䮐䮑䮒䮓䮔䮕䮖䮗䮘䮙䮚䮛䮜䮝䮞䮟䮠䮡䮢䮣䮤䮥䮦䮧䮨䮩䮪䮫䮬䮭䮮䮯䮰䮱䮲䮳䮴䮵䮶䮷䮸䮹䮺䮻䮼䮽䮾䮿䯀䯁䯂䯃䯄䯅䯆䯇䯈䯉䯊䯋䯌䯍䯎䯏䯐䯑䯒䯓䯔䯕䯖䯗䯘䯙䯚䯛䯜䯝䯞䯟䯠䯡䯢䯣䯤䯥䯦䯧䯨䯩䯪䯫䯬䯭䯮䯯䯰䯱䯲䯳䯴䯵䯶䯷䯸䯹䯺䯻䯼䯽䯾䯿䰀䰁䰂䰃䰄䰅䰆䰇䰈䰉䰊䰋䰌䰍䰎䰏䰐䰑䰒䰓䰔䰕䰖䰗䰘䰙䰚䰛䰜䰝䰞䰟䰠䰡䰢䰣䰤䰥䰦䰧䰨䰩䰪䰫䰬䰭䰮䰯䰰䰱䰲䰳䰴䰵䰶䰷䰸䰹䰺䰻䰼䰽䰾䰿䱀䱁䱂䱃䱄䱅䱆䱇䱈䱉䱊䱋䱌䱍䱎䱏䱐䱑䱒䱓䱔䱕䱖䱗䱘䱙䱚䱛䱜䱝䱞䱟䱠䱡䱢䱣䱤䱥䱦䱧䱨䱩䱪䱫䱬䱭䱮䱯䱰䱱䱲䱳䱴䱵䱶䱷䱸䱹䱺䱻䱼䱽䱾䱿䲀䲁䲂䲃䲄䲅䲆䲇䲈䲉䲊䲋䲌䲍䲎䲏䲐䲑䲒䲓䲔䲕䲖䲗䲘䲙䲚䲛䲜䲝䲞䲟䲠䲡䲢䲣䲤䲥䲦䲧䲨䲩䲪䲫䲬䲭䲮䲯䲰䲱䲲䲳䲴䲵䲶䲷䲸䲹䲺䲻䲼䲽䲾䲿䳀䳁䳂䳃䳄䳅䳆䳇䳈䳉䳊䳋䳌䳍䳎䳏䳐䳑䳒䳓䳔䳕䳖䳗䳘䳙䳚䳛䳜䳝䳞䳟䳠䳡䳢䳣䳤䳥䳦䳧䳨䳩䳪䳫䳬䳭䳮䳯䳰䳱䳲䳳䳴䳵䳶䳷䳸䳹䳺䳻䳼䳽䳾䳿䴀䴁䴂䴃䴄䴅䴆䴇䴈䴉䴊䴋䴌䴍䴎䴏䴐䴑䴒䴓䴔䴕䴖䴗䴘䴙䴚䴛䴜䴝䴞䴟䴠䴡䴢䴣䴤䴥䴦䴧䴨䴩䴪䴫䴬䴭䴮䴯䴰䴱䴲䴳䴴䴵䴶䴷䴸䴹䴺䴻䴼䴽䴾䴿䵀䵁䵂䵃䵄䵅䵆䵇䵈䵉䵊䵋䵌䵍䵎䵏䵐䵑䵒䵓䵔䵕䵖䵗䵘䵙䵚䵛䵜䵝䵞䵟䵠䵡䵢䵣䵤䵥䵦䵧䵨䵩䵪䵫䵬䵭䵮䵯䵰䵱䵲䵳䵴䵵䵶䵷䵸䵹䵺䵻䵼䵽䵾䵿䶀䶁䶂䶃䶄䶅䶆䶇䶈䶉䶊䶋䶌䶍䶎䶏䶐䶑䶒䶓䶔䶕䶖䶗䶘䶙䶚䶛䶜䶝䶞䶟䶠䶡䶢")
                .setLastName(faker.name().lastName())
                .setAddress(faker.address().streetAddress())
                .build();

                ProducerRecord<Long, Customer> record = new ProducerRecord<>(topicName, id, customer);
                logger.info("Sending Key = {}, Value = {}", record.key(), record.value());
                producer.send(record, (recordMetadata, exception) -> sendCallback(record, recordMetadata, exception));
                id++;
                TimeUnit.MILLISECONDS.sleep(messageBackOff);
            }
        }
    }

    private void sendCallback(ProducerRecord<Long, Customer> record, RecordMetadata recordMetadata, Exception e) {
        if (e == null) {
            logger.debug("succeeded sending. offset: {}", recordMetadata.offset());
        } else {
            logger.error("failed sending key: {}" + record.key(), e);
        }
    }

    private Map<String, String> defaultProps = Map.of(
            ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, "broker:9092",
            ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, "org.apache.kafka.common.serialization.LongSerializer",
            ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, "io.confluent.kafka.serializers.KafkaAvroSerializer");

    private Properties buildProperties(Map<String, String> baseProps, Map<String, String> envProps, String prefix) {
        Map<String, String> systemProperties = envProps.entrySet()
                .stream()
                .filter(e -> e.getKey().startsWith(prefix))
                .filter(e -> !e.getValue().isEmpty())
                .collect(Collectors.toMap(
                        e -> e.getKey()
                                .replace(prefix, "")
                                .toLowerCase()
                                .replace("_", "."),
                        e -> e.getValue()));

        Properties props = new Properties();
        props.putAll(baseProps);
        props.putAll(systemProperties);
        return props;
    }

    private void createTopic(AdminClient adminClient, String topicName, Integer numberOfPartitions,
            Short replicationFactor) throws InterruptedException, ExecutionException {
        if (!adminClient.listTopics().names().get().contains(topicName)) {
            logger.info("Creating topic {}", topicName);

            final Map<String, String> configs = replicationFactor < 3
                    ? Map.of(TopicConfig.MIN_IN_SYNC_REPLICAS_CONFIG, "1")
                    : Map.of();

            final NewTopic newTopic = new NewTopic(topicName, numberOfPartitions, replicationFactor);
            newTopic.configs(configs);
            try {
                CreateTopicsResult topicsCreationResult = adminClient.createTopics(Collections.singleton(newTopic));
                topicsCreationResult.all().get();
            } catch (ExecutionException e) {
                // silent ignore if topic already exists
            }
        }
    }
}
